#!/usr/bin/env bash
#
# Smoke test: every URL must answer 2xx or 3xx from outside the cluster —
# through DNS, the ALB, its TLS certificate and its routing rules, the same
# path a user's request takes.
#
#   smoke.sh https://dev.example.com/ https://dev.example.com/api/auth/health
#
# Each URL gets 6 tries, 10s apart: the first seconds after a rollout can still
# hit a target the ALB is draining. Anything still failing after that is a
# failed release.

set -euo pipefail

failed=0
for url in "$@"; do
  ok=false
  for attempt in 1 2 3 4 5 6; do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "${url}" 2>/dev/null || echo 000)"
    if [[ "${code}" =~ ^[23][0-9][0-9]$ ]]; then
      echo "  ok    ${code}  ${url}"
      ok=true
      break
    fi
    sleep 10
  done
  if [[ "${ok}" != true ]]; then
    echo "  FAIL  ${code}  ${url}  (after 6 tries)"
    failed=1
  fi
done

exit "${failed}"
