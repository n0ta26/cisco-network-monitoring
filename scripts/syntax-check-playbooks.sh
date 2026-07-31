#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
playbooks_dir="${repository_root}/ansible/playbooks"
inventory="${repository_root}/ansible/inventory.yml"
playbook_found=false

export ANSIBLE_CONFIG="${repository_root}/ansible/ansible.cfg"

while IFS= read -r playbook; do
  playbook_found=true
  echo "Syntax checking ${playbook#"${repository_root}/"}"
  ansible-playbook -i "${inventory}" "${playbook}" --syntax-check
done < <(
  find "${playbooks_dir}" -type f \( -name '*.yml' -o -name '*.yaml' \) |
    LC_ALL=C sort
)

if [[ "${playbook_found}" == false ]]; then
  echo "No playbooks found under ${playbooks_dir}" >&2
  exit 1
fi
