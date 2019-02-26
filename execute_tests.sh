#!/bin/bash

## Deploy virtualenv for testing environment molecule/ansible-playbook/infratest

## Shell Opts ----------------------------------------------------------------

set -x
set -o pipefail
export ANSIBLE_HOST_KEY_CHECKING=False

## Variables -----------------------------------------------------------------

SYS_VENV_NAME="${SYS_VENV_NAME:-venv-molecule}"
SYS_CONSTRAINTS="constraints.txt"
SYS_REQUIREMENTS="requirements.txt"
SYS_INVENTORY="${SYS_INVENTORY:-/etc/openstack_deploy/openstack_inventory.json}"

SKIP_CONVERGE=false
SKIP_VERIFY=false

MOLECULES=()
SCENARIOS=()

## Remove Ansible Plug-ins Prior to System Tests Execution

rm -rf /root/.ansible/plugins

## Functions -----------------------------------------------------------------

usage() {
  echo -n "execute_tests [-p] [-m MOLECULE_PATH(S)] [--sc|skip-converge] [--sv|skip-verify]
Execute Molecule tests.

 Options:
  -p      Set 'MNAIO_SSH' env var for testing MNAIO topology in Phobos
  -m      Path of single Molecule to execute
  -s      Scenario to execute
  --sc    Skip the Molecule converge stage [--skip-converge]
  --sv    Skip the Molecule verify stage [--skip-verify]
  -h      Display this help and exit
"
}

## Parse Args ----------------------------------------------------------------

while getopts ":pm:s:-:h" opt;
do
  case ${opt} in
    p)
      export MNAIO_SSH="ssh -ttt -oStrictHostKeyChecking=no root@infra1"
      ;;
    m)
      MOLECULES+=("$OPTARG")
      ;;
    s)
      SCENARIOS+=("$OPTARG")
      ;;
    -)
      case ${OPTARG} in
        skip-converge)
          SKIP_CONVERGE=true
          ;;
        sc)
          SKIP_CONVERGE=true
          ;;
        skip-verify)
          SKIP_VERIFY=true
          ;;
        sv)
          SKIP_VERIFY=true
          ;;
        *)
          echo error "Invalid option: --${OPTARG}" >&2
          usage
          exit 1
          ;;
      esac
      ;;
    h)
      usage
      exit 1
      ;;
    \?)
      echo error "Invalid option: -$OPTARG" >&2
      usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

## Main ----------------------------------------------------------------------

# Determine if the user specified a specific Molecule to execute or not
if [ "${#MOLECULES[@]}" -eq 0 ]; then
    MOLECULES=(molecules/*)
fi
echo "Preparing to test MOLECULES '${MOLECULES[*]}'"

# Determine if the user specified a specific scenario to execute or not
if [ "${#SCENARIOS[@]}" -eq 0 ]; then
    SCENARIOS=(default)
fi
echo "Preparing to test SCENARIOS '${SCENARIOS[*]}'"

# fail hard during setup
set -e
# Create virtualenv for molecule
virtualenv --no-pip --no-setuptools --no-wheel "${SYS_VENV_NAME}"

# Activate virtualenv
source "${SYS_VENV_NAME}/bin/activate"

# Ensure that correct pip version is installed
PIP_TARGET="$(awk -F= '/^pip==/ {print $3}' ${SYS_CONSTRAINTS})"
VENV_PYTHON="${SYS_VENV_NAME}/bin/python"
VENV_PIP="${SYS_VENV_NAME}/bin/pip"

if [[ "$(${VENV_PIP} --version 2>/dev/null)" != "pip ${PIP_TARGET}"* ]]; then
    CURL_CMD="curl --silent --show-error --retry 5"
    OUTPUT_FILE="get-pip.py"
    ${CURL_CMD} https://bootstrap.pypa.io/get-pip.py > ${OUTPUT_FILE}  \
        || ${CURL_CMD} https://raw.githubusercontent.com/pypa/get-pip/master/get-pip.py > ${OUTPUT_FILE}
    GETPIP_OPTIONS="pip setuptools wheel --constraint ${SYS_CONSTRAINTS}"
    ${VENV_PYTHON} ${OUTPUT_FILE} ${GETPIP_OPTIONS} \
        || ${VENV_PYTHON} ${OUTPUT_FILE} --isolated ${GETPIP_OPTIONS}
fi

# Install test suite requirements
PIP_OPTIONS="-r ${SYS_REQUIREMENTS}"
${VENV_PIP} install ${PIP_OPTIONS} || ${VENV_PIP} install --isolated ${PIP_OPTIONS}

# Generate moleculerized inventory from openstack-ansible dynamic inventory
echo "+-------------------- ANSIBLE INVENTORY --------------------+"
if [[ -e ${SYS_INVENTORY} ]]; then
  echo "Local inventory source found."
  cp ${SYS_INVENTORY} dynamic_inventory.json
else
  echo "No local inventory source found, copying from MNAIO infra1 node instead."
  rsync infra1:${SYS_INVENTORY} dynamic_inventory.json
fi
cat dynamic_inventory.json
echo "+-------------------- ANSIBLE INVENTORY --------------------+"

# Run molecule converge and verify
set +e # allow test stages to return errors
for TEST in "${MOLECULES[@]}" ; do
    # Introspect all scenarios from given molecule
    ALL_SCENARIOS=()
    SCENARIO_PATHS=($TEST/molecule/*)
    for path in "${SCENARIO_PATHS[@]}"; do
        ALL_SCENARIOS+=("${path##*/}")
    done
    # The molecule.yml file for all scenarios needs to be valid for any of
    # them to work.  So, we first generate them all before focusing on the
    # ones specified by the user.
    for SCENARIO in "${ALL_SCENARIOS[@]}" ; do
        moleculerize --scenario "${SCENARIO}" --output "$TEST/molecule/$SCENARIO/molecule.yml" dynamic_inventory.json
    done
    # Resume normal operation.
    for SCENARIO in "${SCENARIOS[@]}" ; do
        moleculerize --scenario "${SCENARIO}" --output "$TEST/molecule/$SCENARIO/molecule.yml" dynamic_inventory.json
        pushd "$TEST"
        repo_uri=$(git remote -v | awk '/fetch/{print $2}')
        echo "TESTING: $repo_uri at SHA $(git rev-parse HEAD)"

        # Capture the molecule test repo in the environment so "pytest-rpc" can record it.
        export MOLECULE_TEST_REPO=$(echo ${repo_uri} | rev | cut -d'/' -f1 - | rev | cut -d. -f1)

        # Capture the SHA of the tests we are executing
        export MOLECULE_GIT_COMMIT=$(git rev-parse HEAD)

        # Execute the converge step
        if [[ "${SKIP_CONVERGE}" = false ]]; then
            molecule --debug converge --scenario-name "${SCENARIO}"
        else
            echo "Skipping converge step!"
        fi

        if [[ $? -ne 0 ]] && RC=$?; then  # do not run tests if converge fails
            echo "CONVERGE: Failure in $(basename ${TEST}) for scenario ${SCENARIO}, verify step being skipped"
            continue
        fi

        # Execute the verify step
        if [[ "${SKIP_VERIFY}" = false ]]; then
            molecule --debug verify --scenario-name "${SCENARIO}"
        else
            echo "Skipping verify step!"
        fi

        [[ $? -ne 0 ]] && RC=$?  # record non-zero exit code
        popd
    done
done

# Gather junit.xml results if verify stage was executed
if [[ "${SKIP_VERIFY}" = false ]]; then
    rm -f test_results.tar  # ensure any previous results are deleted
    ls  molecules/*/molecule/*/*.xml | tar -cvf test_results.tar --files-from=-

    # Gather pytest debug files
    ls  molecules/*/molecule/*/pytestdebug.log | tar -rvf test_results.tar --files-from=-
fi

# if exit code is recorded, use it, otherwise let it exit naturally
[[ -z ${RC+x} ]] && exit ${RC}
