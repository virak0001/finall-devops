#!/usr/bin/env bash
#
# The release tag (vX.Y.Z) on one commit of a service repository — what the
# promote job names a prod image after. Runs in alpine/k8s (git, bash) with
# the workspace mounted; see vars/imageTag.groovy.
#
#   release-tag.sh <short-sha>
#
# Environment: GH_USER GH_TOKEN (read access), REPO (host/path.git, no
# scheme), OUT. Writes VERSION=vX.Y.Z, or VERSION= when the commit has none.
# The highest wins when a commit carries several.
#
# The token is only in the URL handed to one git command, with tracing off.

set -euo pipefail
set +x

sha="${1:?usage: release-tag.sh <short-sha>}"
OUT="${OUT:-.platform/release.env}"
mkdir -p "$(dirname "${OUT}")"
: > "${OUT}"

# RELEASE_URL overrides the remote entirely — for testing without a token.
url="${RELEASE_URL:-https://${GH_USER:-}:${GH_TOKEN:-}@${REPO}}"
if ! refs="$(git ls-remote --tags "${url}" 2>&1)"; then
  if [[ -n "${GH_TOKEN:-}" ]]; then refs="${refs//${GH_TOKEN}/****}"; fi
  echo "error: could not list the tags of ${REPO}:" >&2
  echo "${refs}" | sed 's/^/    /' >&2
  exit 1
fi

# An annotated tag is listed twice: its own object, and "^{}" — the commit it
# points at. A lightweight tag is listed once, at the commit. Either way the
# line whose hash starts with the commit names the tag.
version="$(printf '%s\n' "${refs}" \
  | awk -v s="${sha}" 'index($1, s) == 1 { t = $2; sub("^refs/tags/", "", t); sub("\\^\\{\\}$", "", t); print t }' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sed 's/^v//' | sort -u -t. -k1,1n -k2,2n -k3,3n | tail -1 | sed 's/^./v&/')" || true

printf 'VERSION=%s\n' "${version}" >> "${OUT}"
if [[ -n "${version}" ]]; then
  echo "${REPO} ${sha} is release ${version}"
else
  echo "${REPO} ${sha} has no vX.Y.Z tag"
fi
