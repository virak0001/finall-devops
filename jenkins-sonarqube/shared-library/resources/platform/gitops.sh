#!/usr/bin/env bash
#
# GitOps operations on the cluster repository. Runs inside alpine/k8s (git,
# bash, python3) with the workspace mounted — see vars/gitops.groovy.
#
#   gitops.sh get-tag      <env> <service>
#   gitops.sh previous-tag <env> <service>
#   gitops.sh set-tag      <env> <service> <tag> <message-file>
#
# Environment: GH_USER GH_TOKEN (a token with write access), REPO
# (host/path.git, no scheme), BRANCH, OUT (where results are written).
#
# The token is only ever in a URL passed as an argument to one git command —
# never written to .git/config — and this script runs with tracing off, so it
# reaches neither the disk nor the build log.

set -euo pipefail
set +x

cmd="${1:?usage: gitops.sh get-tag|previous-tag|set-tag ...}"
shift

DIR=".gitops"
# GITOPS_URL overrides the remote entirely — a local path, for testing this
# script without GitHub.
URL="${GITOPS_URL:-https://${GH_USER:-}:${GH_TOKEN:-}@${REPO}}"
OUT="${OUT:-.platform/result.env}"
mkdir -p "$(dirname "${OUT}")"
: > "${OUT}"

export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
export GIT_CONFIG_KEY_1=user.name      GIT_CONFIG_VALUE_1="${GIT_AUTHOR_NAME:-jenkins}"
export GIT_CONFIG_KEY_2=user.email     GIT_CONFIG_VALUE_2="${GIT_AUTHOR_EMAIL:-jenkins@ci.local}"

# Fresh every time. A clone left by an earlier build may sit on a commit that
# has since been superseded, and set-tag on that would push a stale file.
clone() {
  rm -rf "${DIR}"
  # Depth 100: previous-tag walks this much history. A tag older than 100
  # commits to the env file is past any sane rollback window anyway.
  git clone --quiet --depth 100 --branch "${BRANCH}" "${URL}" "${DIR}"
}

result() { printf '%s=%s\n' "$1" "$2" >> "${OUT}"; }

case "${cmd}" in
  get-tag)
    env="$1"; service="$2"
    clone
    tag="$("${DIR}/scripts/service.sh" get-tag "${env}" "${service}")"
    result TAG "${tag}"
    echo "${service} runs ${tag} in ${env}"
    ;;

  previous-tag)
    # The tag the service ran before the current one: walk the env file's
    # history newest first and return the first tag that differs from today's.
    # Distinct, not merely the previous commit — a commit that only moved
    # another service's tag did not change this one.
    env="$1"; service="$2"
    clone
    file="helm/env/${env}.yaml"
    current="$("${DIR}/scripts/service.sh" get-tag "${env}" "${service}")"
    previous=""
    tmp="$(mktemp)"
    for sha in $(git -C "${DIR}" log --format=%H -- "${file}"); do
      git -C "${DIR}" show "${sha}:${file}" > "${tmp}" 2>/dev/null || continue
      t="$("${DIR}/scripts/service.sh" get-tag "${env}" "${service}" "${tmp}" 2>/dev/null || true)"
      if [[ -n "${t}" && "${t}" != "${current}" ]]; then
        previous="${t}"
        break
      fi
    done
    rm -f "${tmp}"
    if [[ -z "${previous}" ]]; then
      echo "error: no earlier tag for ${service} in ${env} within the last 100 commits" >&2
      exit 1
    fi
    result CURRENT_TAG "${current}"
    result TAG "${previous}"
    echo "${service} in ${env}: ${current} now, ${previous} before it"
    ;;

  set-tag)
    env="$1"; service="$2"; tag="$3"
    # Absolute: every git command below runs with -C into the clone, where a
    # relative path would point somewhere else.
    message="$(cd "$(dirname "$4")" && pwd)/$(basename "$4")"
    file="helm/env/${env}.yaml"
    clone
    previous="$("${DIR}/scripts/service.sh" get-tag "${env}" "${service}")"
    result PREVIOUS_TAG "${previous}"

    # The cluster repo's own script, so CI and a person edit the file the same
    # way — and it refuses a service with no entry instead of inventing one.
    (cd "${DIR}" && ./scripts/service.sh set-tag "${env}" "${service}" "${tag}")

    if git -C "${DIR}" diff --quiet; then
      result CHANGED false
      result COMMIT "$(git -C "${DIR}" rev-parse HEAD)"
      echo "${service} is already ${tag} in ${env} — nothing to commit"
      exit 0
    fi

    git -C "${DIR}" add "${file}"
    # Authored by the person behind the deploy, committed by Jenkins — GitHub
    # then shows "<person> authored, jenkins committed". Only a well-formed
    # "Name <email>" is used; anything else leaves the author as jenkins.
    author=()
    if [[ "${GIT_DEPLOY_AUTHOR:-}" =~ ^[^\<\>]+\ \<[^\<\>@]+@[^\<\>]+\>$ ]]; then
      author=(--author "${GIT_DEPLOY_AUTHOR}")
    fi
    git -C "${DIR}" commit --quiet "${author[@]}" -F "${message}"

    # Several pipelines push to this one branch, so another can land between
    # the clone and the push. Rebase and retry: the commits touch different
    # lines, so the rebase is clean — and if it is not, that is a real
    # conflict worth failing on.
    n=0
    until err="$(git -C "${DIR}" push --quiet "${URL}" "HEAD:${BRANCH}" 2>&1)"; do
      n=$((n + 1))
      if [[ ${n} -ge 4 ]]; then
        # git's own message says why — an expired token reads very differently
        # from a race — but it can echo the remote URL, so the token is masked.
        echo "error: push to ${BRANCH} rejected ${n} times:" >&2
        if [[ -n "${GH_TOKEN:-}" ]]; then err="${err//${GH_TOKEN}/****}"; fi
        echo "${err}" | sed 's/^/    /' >&2
        exit 1
      fi
      echo "push rejected — rebasing onto ${BRANCH} (attempt ${n})"
      sleep $((n * 2))
      git -C "${DIR}" pull --quiet --rebase "${URL}" "${BRANCH}"
    done

    result CHANGED true
    result COMMIT "$(git -C "${DIR}" rev-parse HEAD)"
    echo "${env}: ${service} ${previous} -> ${tag}  ($(git -C "${DIR}" rev-parse --short HEAD))"
    ;;

  *)
    echo "unknown command: ${cmd}" >&2
    exit 1
    ;;
esac

rm -rf "${DIR}"
