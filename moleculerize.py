#!/usr/bin/env python
# ======================================================================================================================
# Imports
# ======================================================================================================================
import sys
import json
from argparse import ArgumentParser
from jinja2 import Environment, FileSystemLoader


# ======================================================================================================================
# Globals
# ======================================================================================================================
TEMPLATES_DIR = 'templates'
TEMPLATE = 'molecule.yml.j2'
OUTPUT_FILE = 'molecule.yml'


# ======================================================================================================================
# Functions
# ======================================================================================================================
def _load_input_file(file_path):
    """Read and validate the input file contents.

    Args:
        file_path (str): A string representing a valid file path.

    Returns:
        dict: The exit code to return to the shell.

    Raises:
        RuntimeError: invalid path.
    """

    try:
        with open(file_path, 'r') as f:
            json_inventory = json.loads(f.read())
    except IOError:
        raise RuntimeError('Invalid file path!')

    return json_inventory


def generate_hosts_inventory(json_inventory):
    """Build a dictionary of hosts and associated groups from a Ansible JSON inventory file as keys.

    Args:
        json_inventory (dict): A dictionary object representing a Ansible JSON inventory file.

    Returns:
        dict(list(str)): A dictionary of hosts with each host having a list of associated groups.
    """

    inventory_hosts = {k: [] for k in json_inventory['_meta']['hostvars'].keys()}
    inventory_groups = {k: v for (k, v) in json_inventory.items() if k != '_meta'}

    for group_name, group_info in inventory_groups.items():
        if 'hosts' in group_info.keys():
            for host in group_info['hosts']:
                inventory_hosts[host].append(group_name)

    return inventory_hosts


def render_molecule_template(inventory_hosts, template_file):
    """Create a molecule config file from a template.

    Args:
        inventory_hosts (dict(list(str)): A dictionary of inventory hosts with each host having a list of associated
            groups.
        template_file (str): The template file to use for rendering.

    Returns:
        str: A molecule config file populated with hosts and groups.
    """

    j2_env = Environment(loader=FileSystemLoader(TEMPLATES_DIR), trim_blocks=True)

    return j2_env.get_template(template_file).render(hosts=inventory_hosts)


# ======================================================================================================================
# Main
# ======================================================================================================================
def parse_cmdline(argv):
    """Parse command-line arguments.

    Args:
        argv (sys.argv): The raw command-line input from the user.

    Returns:
        Namespace: A object containing all valid command-line arguments.
    """

    parser = ArgumentParser(description='Create a Molecule compliant config file.')
    parser.add_argument('inv_file', help='File path to dynamic Ansible inventory file.')
    parser.add_argument('--template',
                        default=TEMPLATE,
                        help='Molecule config template file name. (Assumes file in "templates" directory)')
    parser.add_argument('--output', default=OUTPUT_FILE, help='Output file path for molecule config.')

    return parser.parse_args(args=argv[1:])


def main(argv):
    """Main program routine.

    Args:
        argv (sys.argv): The raw command-line input from the user.

    Returns:
        int: The exit code to return to the shell.
    """

    exit_code = 0

    args = parse_cmdline(argv)

    try:
        inventory_hosts = generate_hosts_inventory(_load_input_file(args.inv_file))

        with open(args.output, 'wb') as f:
            f.write(render_molecule_template(inventory_hosts, args.template))

        print("Inventory file: {}".format(args.inv_file))
        print("Template file: {0}/{1}".format(TEMPLATES_DIR, args.template))
        print("Output file: {}".format(args.output))

        print("\nSuccess!")
    except RuntimeError as e:
        exit_code = 1
        print(e)

        print("\nFailed!")

    return exit_code


if __name__ == '__main__':
    sys.exit(main(sys.argv))
