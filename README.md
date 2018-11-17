System Tests for Rackspace Private Cloud - OpenStack
====================================================

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
git submodule add -b master [URL to Git repo] molecules/[name of Git repo]
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

Execute Molecule Tests via Script
---------------------------------
The bash script `execute_tests.sh` has been provided to assist in executing the Molecule test suites
included as git submodules. (Assumes that git submodules have been initialized and recursively updated)

By default the `execute_tests.sh` script assumes that execution was triggered within a CI environment.
In order to execute Molecule tests in a developer MNAIO test environment on Phobos the `-p` CLI option
must be specified.

Example:
```
$ ./execute_tests.sh -p
```

Also, it is possible to execute a single Molecule test suite by supplying a Molecule path to the `-m` flag:
```
$ ./execute_tests.sh -p -m molecules/molecule-rpc-openstack-post-deploy
```

Virtualenv Deployment
---------------------

The creation of the python virtualenv is handled as part of the
`execute_tests.sh` script. It is usually more convenient to execute this
script with a bogus module path or to abort the script after the virtualenv is
deployed.

TODO: [ASC-1185](https://rpc-openstack.atlassian.net/browse/ASC-1185) Create an
option in `execute_scripts.sh` to terminate without executing molecule tests.

If you wish to deploy the virtualenv manually, here are the steps to do so.

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

The creation of the molecule config is handled as part of the
`execute_tests.sh` script. It is usually more convenient to execute this
script and allow it to create the create the molecule config file for each
molecule in scope.

TODO: [ASC-1185](https://rpc-openstack.atlassian.net/browse/ASC-1185) Create an
option in `execute_scripts.sh` to terminate without executing molecule tests.

If you wish to generate a molecule config  manually, here are the steps to do so.

The `moleculerize` tool will build molecule config files from a RPC-O Ansible dynamic inventory file. As a
prerequisite to using the `moleculerize` tool, a dynamic inventory must be generated from a RPC-O build:

```
sudo su -
cd /opt/openstack-ansible/playbooks/inventory
./dynamic_inventory.py > /path/to/dynamic_inventory.json
```

Now you can generate a `molecule.yml` config file using the `moleculerize` tool:

```
cd /path/to/rpc-openstack-system-tests
moleculerize /path/to/dynamic_inventory.json
```

The above command assumes that `moleculerize`'s built-in `molecule.yml.j2` template will be used along with
`molecule.yml` as the output file.


Lint submodules for test_id conflicts
-------------------------------------
The simplest way to ensure that we don't introduce duplicate `test_id` mark values
is to lint the repository with `flake8`.  For convenience this has been configured to
run with the `tox` tool.  Below is an example of running `tox` and encountering a
duplicated `test_id`.
```
(rpc-openstack-system-tests) MVW10EG8WL:rpc-openstack-system-tests zach2872$ tox
flake8 installed: configparser==3.5.0,enum34==1.1.6,flake8==3.5.0,flake8-pytest-mark==0.5.0,mccabe==0.6.1,pycodestyle==2.3.1,pyflakes==1.6.0
flake8 runtests: PYTHONHASHSEED='1589229466'
flake8 runtests: commands[0] | flake8 --isolated --jobs=1 --select=M --pytest-mark1=name=test_id,enforce_unique_value=true,value_match=uuid
./molecules/molecule-validate-glance-deploy/molecule/default/tests/test_scan_images_and_flavors.py:36:1: M301 @pytest.mark.test_id value is not unique! The '3d77bc35-7a21-11e8-90d1-6a00035510c0' mark value already specified for the 'test_volume_attached' test at line '64' found in the './molecules/molecule-rpc-openstack-post-deploy/molecule/default/tests/test_write_to_attached_storage.py' file!
ERROR: InvocationError for command '/Users/zach2872/repos/rpc-openstack-system-tests/.tox/flake8/bin/flake8 --isolated --jobs=1 --select=M --pytest-mark1=name=test_id,enforce_unique_value=true,value_match=uuid' (exited with code 1)
_________________________________________________________________________________________________ summary __________________________________________________________________________________________________
ERROR:   flake8: commands failed
```
