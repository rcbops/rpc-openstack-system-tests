# ======================================================================================================================
# Imports
# ======================================================================================================================
import sys
import json
import yaml
import moleculerize
from os import getenv
from mock import patch
from StringIO import StringIO
from collections import namedtuple
from unittest import TestCase, skipIf
from contextlib import contextmanager


# ======================================================================================================================
# Globals
# ======================================================================================================================
SKIP_EVERYTHING = False if getenv('SKIP_EVERYTHING') is None else True
JSON_INVENTORY = """
{
    "_meta": {
        "hostvars": {
            "host1": {},
            "host2": {},
            "host3": {},
            "host4": {},
            "host5": {},
            "host6": {}
        }
    },
    "group1_with_hosts": {
        "children": [],
        "hosts": [
            "host1"
        ]
    },
    "group2_with_hosts": {
        "children": [],
        "hosts": [
            "host2",
            "host3"
        ]
    },
    "group3_with_hosts": {
        "children": [],
        "hosts": [
            "host4",
            "host5"
        ]
    },
    "group4_with_children": {
        "children": [
            "group1_with_hosts",
            "group2_with_hosts",
            "group3_with_hosts"
        ],
        "hosts": []
    },
    "group5_with_no_hosts_no_children": {
        "children": [],
        "hosts": []
    }
}
"""


# ======================================================================================================================
# Functions
# ======================================================================================================================
@contextmanager
def captured_output():
    new_out, new_err = StringIO(), StringIO()
    old_out, old_err = sys.stdout, sys.stderr
    try:
        sys.stdout, sys.stderr = new_out, new_err
        yield sys.stdout, sys.stderr
    finally:
        sys.stdout, sys.stderr = old_out, old_err


# ======================================================================================================================
# Test Suites
# ======================================================================================================================
class TestMoleculerizeScript(TestCase):
    """Tests for the moleculerize script."""

    @classmethod
    def setUpClass(cls):
        # Test data
        cls.json_inventory = json.loads(JSON_INVENTORY)

        # Expectations
        cls.groups = {'host1': ['group1_with_hosts', 'group4_with_children'],
                      'host2': ['group2_with_hosts', 'group4_with_children'],
                      'host3': ['group2_with_hosts', 'group4_with_children'],
                      'host4': ['group3_with_hosts', 'group4_with_children'],
                      'host5': ['group3_with_hosts', 'group4_with_children'],
                      'host6': []}

    @skipIf(SKIP_EVERYTHING, 'Skip if we are creating/modifying tests!')
    def test01_load_parse_json_inventory(self):
        """Verify that moleculerize can successfully load a JSON Ansible inventory file."""

        # Setup
        hosts_inventory = moleculerize.generate_hosts_inventory(self.json_inventory)

        # Test
        for host in self.groups.keys():
            self.assertItemsEqual(hosts_inventory[host], self.groups[host])

    @skipIf(SKIP_EVERYTHING, 'Skip if we are creating/modifying tests!')
    def test02_render_template(self):
        """Verify that moleculerize can create a YAML template with correct syntax."""

        # Setup
        hosts_inventory = moleculerize.generate_hosts_inventory(self.json_inventory)
        render_yaml = yaml.load(moleculerize.render_molecule_template(hosts_inventory, moleculerize.TEMPLATE))

        # Expectations
        platforms_exp = [{'name': host, 'groups': self.groups[host]} for host in self.groups.keys() if host != 'host6']
        platforms_exp.append({'name': 'host6'})

        # Test
        self.assertItemsEqual(platforms_exp, render_yaml['platforms'])

    @skipIf(SKIP_EVERYTHING, 'Skip if we are creating/modifying tests!')
    def test03_missing_required_keys(self):
        """Verify that moleculerize will reject JSON Ansible inventory files missing required keys."""

        # Setup
        json_inventory_missing_meta = json.loads('{ "invalid": {} }')
        json_inventory_missing_hostvars = json.loads('{ "_meta": { "invalid": {} } }')

        # Test
        with self.assertRaises(RuntimeError):
            moleculerize.generate_hosts_inventory(json_inventory_missing_meta)

        with self.assertRaises(RuntimeError):
            moleculerize.generate_hosts_inventory(json_inventory_missing_hostvars)

    @skipIf(SKIP_EVERYTHING, 'Skip if we are creating/modifying tests!')
    def test04_invalid_template_path(self):
        """Verify that moleculerize will fail gracefully if the template file cannot be found."""

        # Setup
        hosts_inventory = moleculerize.generate_hosts_inventory(self.json_inventory)

        # Test
        with self.assertRaises(RuntimeError):
            moleculerize.render_molecule_template(hosts_inventory, 'MISSING_TEMPLATE')

    @skipIf(SKIP_EVERYTHING, 'Skip if we are creating/modifying tests!')
    def test05_invalid_inventory_path(self):
        """Verify that moleculerize will fail gracefully if the inventory file cannot be found."""

        # Test
        with self.assertRaises(RuntimeError):
            moleculerize._load_input_file('invalid_path')

    @skipIf(SKIP_EVERYTHING, 'Skip if we are creating/modifying tests!')
    @patch('moleculerize._load_input_file')
    @patch('moleculerize.parse_cmdline')
    @patch('moleculerize.generate_hosts_inventory')
    def test06_invalid_config_path(self, generate_hosts_inventory_mock, parse_cmdline_mock, load_input_file_mock):
        """Verify that moleculerize will fail gracefully if the Molecule config file cannot be written."""

        # Setup
        mock_namespace = namedtuple('Namespace', ['template', 'inv_file', 'output'])

        generate_hosts_inventory_mock.return_value = {}
        parse_cmdline_mock.return_value = mock_namespace(output='/path/does/not/exist', template='', inv_file='')
        load_input_file_mock.return_value = None

        # Expectations
        exit_code_exp = 1

        # Test
        with captured_output():
            exit_code_actual = moleculerize.main([])

        self.assertEqual(exit_code_exp, exit_code_actual)
