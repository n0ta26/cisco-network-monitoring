#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validation_dir="$(mktemp -d "${TMPDIR:-/tmp}/cisco-monitoring-config.XXXXXX")"
validator_user="$(id -u):$(id -g)"

cleanup() {
  rm -rf "${validation_dir}"
}
trap cleanup EXIT

ANSIBLE_CONFIG="${repository_root}/ansible/ansible.cfg" \
  ansible-playbook \
  -i localhost, \
  "${repository_root}/ansible/playbooks/render-monitoring-config.yml" \
  -e "monitoring_config_output_dir=${validation_dir}" \
  "$@"

docker compose \
  -f "${repository_root}/files/compose.yaml" \
  config \
  --quiet

docker run --rm \
  --user "${validator_user}" \
  --entrypoint /bin/promtool \
  -v "${repository_root}/files/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  -v "${validation_dir}/prometheus/rules:/etc/prometheus/rules:ro" \
  prom/prometheus:latest \
  check config /etc/prometheus/prometheus.yml

docker run --rm \
  --user "${validator_user}" \
  --entrypoint /bin/amtool \
  -v "${validation_dir}/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  prom/alertmanager:latest \
  check-config /etc/alertmanager/alertmanager.yml
