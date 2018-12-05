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
Utilize the provided `make` target to initialize and update git submodules.
```
make gather-submodules
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

Execute a single Molecule test suite by supplying a Molecule path to the `-m` flag:
```
$ ./execute_tests.sh -p -m molecules/molecule-rpc-openstack-post-deploy
```

Skip execution of the Molecule converge stage by supplying the `-c` flag:
```
$ ./execute_tests.sh -p -c
```

Skip execution of the Molecule verify stage by supplying the `-v` flag:
```
$ ./execute_tests.sh -p -v
```

Virtualenv Deployment
---------------------

The creation of the python virtualenv is handled as part of the
`execute_tests.sh` script. However, it can be quite convenient to create a
Python virtual environment with Molecule prerequisites installed for a
ready-to-go development environment.

Example:
```
$ ./execute_tests.sh -c -v
```

The `-c` `-v` flags skip the converge stage and verify stage, thus only
creating the Python virtual environment in the directory `venv-molecule`.

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
