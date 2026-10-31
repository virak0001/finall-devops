#!/usr/bin/env bash
#
# Copy docker/ to the instance and bring the stack up.
#
#   scripts/deploy.sh <workspace>
#
# Separate from `make apply` on purpose. Terraform builds the box once;
# everything that changes afterwards lives in docker/ and is applied by
# re-running this. The instance is never rebuilt, because rebuilding it loses
# every Jenkins job and all SonarQube history.

set -euo pipefail

WORKSPACE="${1:-dev}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_DIR=/opt/ci

tf_out() { TF_WORKSPACE="${WORKSPACE}" terraform -chdir="${ROOT}/terraform" output -raw "$1" 2>/dev/null; }

IP="$(tf_out public_ip)" || true
KEY="$(tf_out ssh_command | sed -n 's/.*-i \([^ ]*\).*/\1/p')" || true
KEY="$(eval echo "${KEY:-~/.ssh/id_ed25519}")"

[[ -n "${IP}" ]] || {
  echo "error: no instance for workspace '${WORKSPACE}'." >&2
  echo "         make apply WORKSPACE=${WORKSPACE}" >&2
  exit 1; }

[[ -f "${ROOT}/docker/.env" ]] || {
  echo "error: no docker/.env — it holds the database password." >&2
  echo "         cp docker/.env.example docker/.env" >&2
  echo "         and set SONAR_DB_PASSWORD (openssl rand -base64 24)" >&2
  exit 1; }

grep -qE '^SONAR_DB_PASSWORD=.+' "${ROOT}/docker/.env" || {
  echo "error: SONAR_DB_PASSWORD is empty in docker/.env." >&2
  echo "       Postgres would start with no password and SonarQube could not" >&2
  echo "       connect, which surfaces as SonarQube restarting in a loop." >&2
  exit 1; }

SSH=(ssh -i "${KEY}" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "ubuntu@${IP}")

echo "==> ${IP}"

# cloud-init installs Docker, and takes a couple of minutes on a fresh box. A
# deploy that races it fails on `docker: command not found`, which reads like a
# broken image rather than a timing problem.
echo "==> waiting for bootstrap"
for i in $(seq 60); do
  if "${SSH[@]}" 'test -f /opt/ci/.bootstrap-complete' 2>/dev/null; then break; fi
  [[ $i -eq 60 ]] && { echo "error: cloud-init did not finish in 5 minutes." >&2
                       echo "       ssh in and read: sudo cloud-init status --long" >&2
                       exit 1; }
  sleep 5
done
echo "    docker is ready"

echo "==> copying docker/"
# JENKINS_URL is derived, not stored: the Elastic IP is known here and putting
# it in the committed .env would make that file environment-specific.
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
cp "${ROOT}/docker/docker-compose.yml" "${tmp}/"
grep -v '^JENKINS_URL=' "${ROOT}/docker/.env" > "${tmp}/.env"
echo "JENKINS_URL=http://${IP}:8080" >> "${tmp}/.env"

scp -i "${KEY}" -o StrictHostKeyChecking=accept-new -q \
  "${tmp}/docker-compose.yml" "${tmp}/.env" "ubuntu@${IP}:${REMOTE_DIR}/"

# The Groovy that configures Jenkins at startup. -r because compose bind-mounts
# the directory, and a missing one would mount as an empty dir rather than
# failing — Jenkins would start with no credentials and nothing would say why.
scp -i "${KEY}" -o StrictHostKeyChecking=accept-new -qr \
  "${ROOT}/docker/jenkins" "ubuntu@${IP}:${REMOTE_DIR}/"

echo "==> docker compose up -d"
# --ignore-buildable: Jenkins is built here (jenkins/Dockerfile), not pulled.
# --build: a changed plugins.txt rebuilds it; an unchanged one is a cache hit.
"${SSH[@]}" "cd ${REMOTE_DIR} && docker compose pull -q --ignore-buildable && docker compose up -d --build"

echo
echo "==> waiting for both to answer"
for svc in "Jenkins:8080:/login" "SonarQube:9000:/api/system/status"; do
  name="${svc%%:*}"; rest="${svc#*:}"; port="${rest%%:*}"; path="${rest#*:}"
  printf '    %-10s ' "${name}"
  for i in $(seq 60); do
    if curl -fsS --max-time 5 "http://${IP}:${port}${path}" >/dev/null 2>&1; then
      echo "up"; break
    fi
    [[ $i -eq 60 ]] && echo "not answering after 5 minutes — docker compose logs ${name,,}"
    sleep 5
  done
done

echo
echo "  Jenkins    http://${IP}:8080"
echo "  SonarQube  http://${IP}:9000    (admin / admin on first login)"
echo
echo "Jenkins' initial admin password:"
echo "  make jenkins-password WORKSPACE=${WORKSPACE}"
