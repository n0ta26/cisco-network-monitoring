#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validation_dir="$(mktemp -d "${TMPDIR:-/tmp}/cisco-monitoring-config.XXXXXX")"
validator_user="$(id -u):$(id -g)"
prometheus_image="prom/prometheus:v3.13.1"
alertmanager_image="prom/alertmanager:v0.33.1"

cleanup() {
  rm -rf "${validation_dir}"
}
trap cleanup EXIT

ANSIBLE_CONFIG="${repository_root}/ansible/ansible.cfg" \
  ansible-playbook \
  -i localhost, \
  "${repository_root}/ansible/playbooks/render-monitoring-config.yml" \
  -e "monitoring_config_output_dir=${validation_dir}" \
  -e "@${repository_root}/ansible/tests/fixtures/monitoring-secrets.yml" \
  "$@"

docker compose \
  -f "${repository_root}/files/compose.yaml" \
  config \
  --quiet

compose_images="$(
  docker compose \
    -f "${repository_root}/files/compose.yaml" \
    config \
    --images
)"

for validation_image in "${prometheus_image}" "${alertmanager_image}"; do
  if ! grep -Fqx "${validation_image}" <<<"${compose_images}"; then
    echo "Validation image is not used by Compose: ${validation_image}" >&2
    exit 1
  fi
done

for dashboard in "${repository_root}"/files/grafana/dashboards/*.json; do
  jq --exit-status \
    '.kind == "Dashboard"
      and .apiVersion == "dashboard.grafana.app/v2"
      and (.spec.title | length > 0)
      and (.spec.elements | length > 0)' \
    "${dashboard}" >/dev/null
done

docker run --rm \
  --user "${validator_user}" \
  --entrypoint /bin/promtool \
  -v "${validation_dir}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  -v "${validation_dir}/prometheus/rules:/etc/prometheus/rules:ro" \
  "${prometheus_image}" \
  check config /etc/prometheus/prometheus.yml

docker run --rm \
  --user "${validator_user}" \
  --entrypoint /bin/amtool \
  -v "${validation_dir}/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  "${alertmanager_image}" \
  check-config /etc/alertmanager/alertmanager.yml
