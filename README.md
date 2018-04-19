System Tests for Rackspace Private Cloud - OpenStack
====================================================

*WIP* This project is a work in progress and is subject to breaking changes
and design changes.

The rcp-openstack-system-tests repository contains virtualenv requirements and
constraints for installing the
[molecule framework](https://molecule.readthedocs.io/en/latest/)
for deploying system state via [ansible](https://www.ansible.com/)
and validating that state using the
[infratest](https://testinfra.readthedocs.io/en/latest/) test framework on the
Deployment Host.

Tests are gathered as git submodules under the `molecules` directory. Molecule
should be run against each of the submodules in turn.

This repository is meant to be run on the Deployment Host.

Gather Submodules
-----------------
Since the molecule tests are included as git submodules, they must be
initialized and updated in order to be accessible to the molecule test runner.
```
git submodule init
git submodule update --recursive --remote
```

Adding Submodules
-----------------
The submodules for the tests should have branches that mirror the release
branches for this repository (and the rpc-openstack repository). The
submodules should be set to track the appropriate matching branch. For
example, all submodules in the _pike_ branch of this repo should be set to
track the _pike_ branch of their remote origin.

When adding a new submodule, the branch tracking will need to be performed for
each of the release branches.

Add new submodule in _master_ branch and set it to track _master_ branch for its
remote origin.
```
git submodule add -b master [URL to Git repo]
git submodule init
```

After this has been committed to the _master_ branch, for each release branch,
the commit associated with the submodule addition should be rebased or
cherry-picked to the release branch and the tracking configuration for each
submodule should be changed to reflect the release branch. The following
command can be used to achieve this.
```
git config -f .gitmodules submodule.<path>.branch <branch>
```

Virtualenv Deployment
---------------------

On the Deployment Host, create a python virtualenv and populate it using the included
`requirements.txt` and `constraints.txt` files. This will install `molecule` and
`ansible` into the virtualenv.

Example
```
SYS_VENV_NAME=venv-molecule
SYS_CONSTRAINTS="constraints.txt"
SYS_REQUIREMENTS="requirements.txt"

# Create virtualenv for molecule
virtualenv --no-pip --no-setuptools --no-wheel ${SYS_VENV_NAME}

# Activate virtualenv
source ${SYS_VENV_NAME}/bin/activate

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
PIP_OPTIONS=-r ${SYS_REQUIREMENTS}"
${VENV_PIP} install ${PIP_OPTIONS} || ${VENV_PIP} install --isolated ${PIP_OPTIONS}
```

Generate Molecule Config from Ansible Dynamic Inventory
-------------------------------------------------------

The `moleculerize.py` script will build molecule config files from a RPC-O Ansible dynamic inventory file. As a
prerequisite to using the `moleculerize.py` script a dynamic inventory must be generated from a RPC-O build:

```
sudo su -
cd /opt/openstack-ansible/playbooks/inventory
./dynamic_inventory.py > /path/to/dynaic_inventory.json
```

Now you can generate a `molecule.yml` config file using the `moleculerize.py` script:

```
cd /path/to/rpc-openstack-system-tests
./moleculerize.py /path/to/dynaic_inventory.json
```

The above command assumes that the `templates/molecule.yml.j2` template will be used along with `molecule.yml` as 
the output file.

Execute Molecule Tests
----------------------
For each of the submodules in the `molecules` directory, run the `molecule converge`
command to execute any ansible playbook plays needed to set the system up for
test validation. Then run the `molecule verify` command to validate that the
system state conforms to the defined specifications.

The `molecularize.py` script is used to transpose the Deploy Host's dynamic
inventory JSON output into the yaml format used by molecule internally.

Example:
```
# Assuming that the dynamic inventory script is located at the following location:
/opt/openstack-ansible/playbooks/inventory/dynamic_inventory.py > /tmp/dynamic_inventory.json
for TEST in $(ls molecules) ; do
    ./moleculerize.py --output molecules/$TEST/molecule/default/molecule.yml /tmp/dynamic_inventory.json
    pushd molecules/$TEST
    molecule converge
    molecule verify
    popd
done
```

Execute 'moleculerize.py' Unit Tests
------------------------------------
Execute the unit tests for the `molecularize.py` script use the following commands:

```
cd /path/to/rpc-openstack-system-tests
python -m unittest discover -s tests
```
