#!/bin/bash

## Deploy virualenv for testing enironment molecule/ansible-playbook/infratest

## Shell Opts ----------------------------------------------------------------

set -x
set -o pipefail
export ANSIBLE_HOST_KEY_CHECKING=False

## Variables -----------------------------------------------------------------

SYS_VENV_NAME="${SYS_VENV_NAME:-venv-molecule}"
SYS_CONSTRAINTS="constraints.txt"
SYS_REQUIREMENTS="requirements.txt"
SYS_INVENTORY="${SYS_INVENTORY:-/etc/openstack_deploy/openstack_inventory.json}"

## Main ----------------------------------------------------------------------

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

if [[ "$(${VENV_PIP} --version)" != "pip ${PIP_TARGET}"* ]]; then
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
# for each submodule in ${SYS_TEST_SOURCE}/molecules
set +e # allow test stages to return errors
for TEST in molecules/* ; do
    moleculerize --output "$TEST/molecule/default/molecule.yml" dynamic_inventory.json
    pushd "$TEST"
    repo_uri=$(git remote -v | awk '/fetch/{print $2}')
    echo "TESTING: $repo_uri at SHA $(git rev-parse HEAD)"
    # Capture the molecule test repo in the environment so "pytest-rpc" can record it.
    export MOLECULE_TEST_REPO=$(echo $repo_uri | rev | cut -d'/' -f1 - | rev | cut -d. -f1)
    # Capture the SHA of the tests we are executing
    export MOLECULE_GIT_COMMIT=$(git rev-parse HEAD)
    molecule --debug converge
    if [[ $? -ne 0 ]] && RC=$?; then  # do not run tests if converge fails
        echo "CONVERGE: Failure in $(basename $TEST), verify step being skipped"
        continue
    fi
    molecule --debug verify
    [[ $? -ne 0 ]] && RC=$?  # record non-zero exit code
    popd
done

# Gather junit.xml results
rm -f test_results.tar  # ensure any previous results are deleted
ls  molecules/*/molecule/*/*.xml | tar -cvf test_results.tar --files-from=-
# Gather pytest debug files
ls  molecules/*/molecule/*/pytestdebug.log | tar -rvf test_results.tar --files-from=-

# if exit code is recorded, use it, otherwise let it exit naturally
[[ -z ${RC+x} ]] && exit ${RC}
