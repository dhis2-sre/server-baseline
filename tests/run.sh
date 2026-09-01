#!/usr/bin/env bash
# Builds the collection, installs it somewhere throwaway, and syntax-checks the playbooks against
# that installed copy rather than against this working tree.
#
# Nothing here connects to a host. What it proves is that galaxy.yml is valid, that the tarball
# installs, and that dhis2.sre.baseline and the three roles it composes resolve by their fully
# qualified names - which is how consumers reach them, and the one thing a lint run over the working
# tree cannot tell you, because there every role also resolves by its bare directory name.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

work_dir=$(mktemp --directory)
trap 'rm --recursive --force -- "$work_dir"' EXIT

ansible-galaxy collection build --output-path "$work_dir" -- "$repo_root"

# Pulls ansible.posix in from galaxy.yml's dependencies, so this needs network.
ansible-galaxy collection install --collections-path "$work_dir/collections" -- "$work_dir"/dhis2-sre-*.tar.gz

export ANSIBLE_COLLECTIONS_PATH="$work_dir/collections"

# Referenced by collection name, the way a consumer runs it, so a playbook that only resolves
# relative to the working tree fails here.
ansible-playbook --syntax-check --inventory "$repo_root/tests/inventory.ini" dhis2.sre.baseline
ansible-playbook --syntax-check --inventory "$repo_root/tests/inventory.ini" "$repo_root/tests/individual-roles.yml"
