.PHONY: lint gather-submodules develop
.DEFAULT_GOAL := help

SHELL := /bin/bash
export VIRTUALENVWRAPPER_PYTHON := /usr/bin/python

define PRINT_HELP_PYSCRIPT
import re, sys

for line in sys.stdin:
	match = re.match(r'^([a-zA-Z_-]+):.*?## (.*)$$', line)
	if match:
		target, help = match.groups()
		print("%-20s %s" % (target, help))
endef
export PRINT_HELP_PYSCRIPT

help:
	@python -c "$$PRINT_HELP_PYSCRIPT" < $(MAKEFILE_LIST)

lint: ## lint the repository with tox and flake8
	tox

develop: ## install development requirements
	pip install -r requirements.txt

gather-submodules: ## gather all submodules
	git submodule init
	git submodule update --recursive --remote
