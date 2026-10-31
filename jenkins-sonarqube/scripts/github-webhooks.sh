#!/usr/bin/env bash
#
# Point each service repository's GitHub webhook at this Jenkins.
#
#   scripts/github-webhooks.sh <workspace> [--dry-run]
#
# After this, a push or a pull request on any of them is delivered to
# http://<jenkins>:8080/github-webhook/ within seconds, and the repo's
# multibranch job (init.groovy.d/40-github.groovy) builds what changed.
#
# Idempotent: a hook already pointing at this Jenkins is updated (new secret,
# events), never duplicated. Run it again after the Elastic IP changes or the
# secret is rotated.
#
# Needs: the GitHub CLI logged in as someone with admin on every repo
# (`gh auth login`), GITHUB_WEBHOOK_SECRET in docker/.env, and the instance
# applied (its address comes from Terraform).
#
# The cluster repo gets no hook on purpose: the release job runs only when a
# person starts it.

set -euo pipefail

WORKSPACE="${1:-dev}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# owner/repo, one per service — the same list as init.groovy.d/40-github.groovy.
REPOS=(
  virak-01/aws-auth
  virak-01/api-ops
  virak-01/frontend
)

command -v gh >/dev/null 2>&1 || { echo "error: the GitHub CLI (gh) is not installed" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh is not logged in — run: gh auth login" >&2; exit 1; }

secret="$(sed -n 's/^GITHUB_WEBHOOK_SECRET=//p' "${ROOT}/docker/.env" 2>/dev/null | head -1)"
if [[ -z "${secret}" ]]; then
  echo "error: GITHUB_WEBHOOK_SECRET is empty in docker/.env." >&2
  echo "       Set one (openssl rand -hex 32), then make deploy so Jenkins has it too." >&2
  exit 1
fi

ip="$(TF_WORKSPACE="${WORKSPACE}" terraform -chdir="${ROOT}/terraform" output -raw public_ip 2>/dev/null || true)"
[[ -n "${ip}" ]] || { echo "error: no instance for '${WORKSPACE}' — make apply WORKSPACE=${WORKSPACE}" >&2; exit 1; }
url="http://${ip}:8080/github-webhook/"

echo "==> webhook URL ${url}"

for repo in "${REPOS[@]}"; do
  # Ours is the hook already pointing at this Jenkins's endpoint. GitHub never
  # returns a hook's secret, so it cannot be compared — it is always re-sent.
  id="$(gh api "repos/${repo}/hooks" --jq ".[] | select(.config.url == \"${url}\") | .id" 2>/dev/null | head -1 || true)"

  # The body goes through stdin, so the secret is in no command line.
  body="$(python3 - "${url}" "${secret}" <<'PYEOF'
import json, sys
url, secret = sys.argv[1:3]
print(json.dumps({
    "name": "web",
    "active": True,
    # push: branch builds. pull_request: PR builds and their status checks.
    "events": ["push", "pull_request"],
    "config": {"url": url, "content_type": "json", "secret": secret, "insecure_ssl": "0"},
}))
PYEOF
)"

  if [[ "${DRY_RUN}" == true ]]; then
    echo "    ${repo}: would $([[ -n "${id}" ]] && echo "update hook ${id}" || echo "create a hook")"
    continue
  fi

  if [[ -n "${id}" ]]; then
    printf '%s' "${body}" | gh api --method PATCH "repos/${repo}/hooks/${id}" --input - >/dev/null
    echo "    ${repo}: updated hook ${id}"
  else
    id="$(printf '%s' "${body}" | gh api --method POST "repos/${repo}/hooks" --input - --jq .id)"
    echo "    ${repo}: created hook ${id}"
  fi
done

echo
echo "GitHub sends a ping to each new hook. Check it arrived:"
echo "    gh api repos/${REPOS[0]}/hooks/<id>/deliveries --jq '.[0] | {event, status_code}'"
echo "A 200 is Jenkins accepting it; a timeout means the security group (github_hook_cidrs)."
