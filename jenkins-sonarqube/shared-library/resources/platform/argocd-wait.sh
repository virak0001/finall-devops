#!/usr/bin/env bash
#
# Wait until an Argo CD Application runs a given git revision, Synced and
# Healthy, with the expected image. Runs inside alpine/k8s (curl, jq).
#
# Environment:
#   ARGOCD_SERVER   argocd.<site_hostname> — through the ALB, so this machine's
#                   address must be in ADMIN_ALLOWED_CIDRS (cluster project)
#   ARGOCD_TOKEN    token of the `ci` account (controllers/argocd.yaml)
#   APP             e.g. api-service-uat
#   REVISION        the cluster repo commit the deploy pushed
#   IMAGE           the full image reference that must be running
#   SYNC            true: ask Argo CD to sync (prod, which never syncs itself)
#                   false: only refresh, and let auto-sync act (dev, uat)
#   TIMEOUT         seconds, default 600
#
# "Healthy" is Argo CD's word for: every Deployment finished rolling out —
# every new pod passed its readiness probe and, through the load balancer
# controller's readiness gate, the ALB's health check. So this returning 0
# means the new version is serving through the ALB, not merely scheduled.
#
# Exit: 0 healthy at REVISION · 1 failed or degraded · 2 timed out

set -euo pipefail
set +x

: "${ARGOCD_SERVER:?}" "${ARGOCD_TOKEN:?}" "${APP:?}" "${REVISION:?}" "${IMAGE:?}"
SYNC="${SYNC:-false}"
TIMEOUT="${TIMEOUT:-600}"
POLL="${POLL:-10}"              # seconds between checks
SCHEME="${ARGOCD_SCHEME:-https}"  # http only for testing against a stub

api() {  # api <method> <path> [body]
  curl -sS --fail-with-body --max-time 30 -X "$1" \
    -H "Authorization: Bearer ${ARGOCD_TOKEN}" -H 'Content-Type: application/json' \
    ${3:+--data "$3"} "${SCHEME}://${ARGOCD_SERVER}/api/v1/applications/${APP}$2"
}

# Fetch git now instead of waiting up to 3 minutes for the next poll.
api GET '?refresh=normal' > /dev/null

if [[ "${SYNC}" == true ]]; then
  echo "requesting sync of ${APP} to ${REVISION:0:8}"
  api POST /sync "$(jq -nc --arg r "${REVISION}" '{revision: $r, prune: true}')" > /dev/null
fi

deadline=$(( $(date +%s) + TIMEOUT ))
degraded=0
hpa_noted=false
last=""

while :; do
  app="$(api GET '' || true)"
  if [[ -z "${app}" ]] || ! jq -e . >/dev/null 2>&1 <<< "${app}"; then
    echo "  Argo CD API did not answer — retrying"
  else
    rev="$(jq -r '.status.sync.revision // ""' <<< "${app}")"
    sync="$(jq -r '.status.sync.status // ""' <<< "${app}")"
    health="$(jq -r '.status.health.status // ""' <<< "${app}")"
    phase="$(jq -r '.status.operationState.phase // ""' <<< "${app}")"
    oprev="$(jq -r '.status.operationState.syncResult.revision // ""' <<< "${app}")"
    images="$(jq -r '.status.summary.images // [] | join(" ")' <<< "${app}")"

    now="revision=${rev:0:8} sync=${sync} health=${health} operation=${phase:-none}"
    [[ "${now}" != "${last}" ]] && echo "  ${now}"
    last="${now}"

    # A sync of THIS revision that failed outright — bad manifest, quota,
    # admission webhook. Waiting longer will not fix it.
    if [[ "${oprev}" == "${REVISION}" && ( "${phase}" == Failed || "${phase}" == Error ) ]]; then
      echo "error: the sync of ${REVISION:0:8} failed:" >&2
      jq -r '.status.operationState.message // ""' <<< "${app}" | sed 's/^/    /' >&2
      exit 1
    fi

    if [[ "${rev}" == "${REVISION}" ]]; then
      if [[ "${sync}" == Synced && "${health}" == Healthy ]]; then
        if [[ " ${images} " == *" ${IMAGE} "* ]]; then
          echo "${APP} is Healthy at ${REVISION:0:8}, running ${IMAGE##*/}"
          exit 0
        fi
        echo "  Synced and Healthy, but ${IMAGE##*/} is not among: ${images:-none}"
      fi
      # Degraded right after a sync is normal for a few seconds while old pods
      # terminate. Six polls in a row (a minute, at the default interval) is a
      # crash loop.
      #
      # Except when the HorizontalPodAutoscaler is the only Degraded object:
      # for the first minute or two after a rollout the new pod has no CPU
      # metrics yet ("did not receive metrics for targeted pods"), and Argo CD
      # reports the HPA, and so the whole app, as Degraded. That is a release
      # still starting, not a failing one — it keeps waiting, and still has to
      # reach Healthy before the timeout.
      broken="$(jq -r '[.status.resources[]? | select(.health.status == "Degraded" and .kind != "HorizontalPodAutoscaler")] | length' <<< "${app}")"
      if [[ "${health}" == Degraded && "${broken}" == 0 ]]; then
        if [[ "${hpa_noted}" == false ]]; then
          echo "  only the HPA is Degraded — waiting for the new pods' metrics"
          hpa_noted=true
        fi
        degraded=0
      elif [[ "${health}" == Degraded ]]; then
        degraded=$((degraded + 1))
        if [[ ${degraded} -ge 6 ]]; then
          echo "error: ${APP} has been Degraded for a minute at ${REVISION:0:8}" >&2
          jq -r '.status.resources[]? | select(.health.status == "Degraded")
                 | "    \(.kind)/\(.name): \(.health.message // "")"' <<< "${app}" >&2
          exit 1
        fi
      else
        degraded=0
      fi
    fi
  fi

  if [[ $(date +%s) -ge ${deadline} ]]; then
    echo "error: ${APP} did not become Healthy at ${REVISION:0:8} within ${TIMEOUT}s" >&2
    exit 2
  fi
  sleep "${POLL}"
done
