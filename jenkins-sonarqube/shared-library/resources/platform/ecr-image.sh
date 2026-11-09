#!/usr/bin/env bash
#
# Image names in ECR, for the pipelines. Runs in the pinned aws-cli image with
# the workspace mounted (vars/imageTag.groovy); credentials come from the
# instance profile.
#
#   ecr-image.sh find <repository> <tag>
#       FOUND=true DIGEST=… TAGS=a,b   or   FOUND=false
#
#   ecr-image.sh add <repository> <existing-tag> <new-tag>
#       Give the image <existing-tag> names a second name. Nothing is pulled,
#       pushed or rebuilt: the same manifest is put again under the new tag,
#       so the digest — the image — is identical. Refuses when <new-tag>
#       already names a different image (ECR tags are immutable).
#
# Results go to OUT as KEY=value lines. A lookup that cannot run (no
# credentials, no repository) fails loudly: it must never read as "not built".

set -euo pipefail

cmd="${1:?usage: ecr-image.sh find|add ...}"
shift

OUT="${OUT:-.platform/ecr.env}"
mkdir -p "$(dirname "${OUT}")"
: > "${OUT}"
result() { printf '%s=%s\n' "$1" "$2" >> "${OUT}"; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Prints "<digest><TAB><tag,tag,...>". Exit 3 when the tag is not there.
lookup() {
  local repo="$1" tag="$2"
  if aws ecr describe-images --repository-name "${repo}" --image-ids "imageTag=${tag}" \
       --query 'imageDetails[0].[imageDigest, join(`,`, imageTags)]' --output text 2> "${TMP}/err"; then
    return 0
  fi
  if grep -q ImageNotFoundException "${TMP}/err"; then
    return 3
  fi
  cat "${TMP}/err" >&2
  return 1
}

case "${cmd}" in
  find)
    repo="$1"; tag="$2"
    rc=0; info="$(lookup "${repo}" "${tag}")" || rc=$?
    case "${rc}" in
      0) result FOUND true
         result DIGEST "$(cut -f1 <<< "${info}")"
         result TAGS "$(cut -f2 <<< "${info}")"
         echo "${repo}:${tag} is in ECR — $(cut -f2 <<< "${info}")" ;;
      3) result FOUND false
         echo "${repo}:${tag} is not in ECR" ;;
      *) echo "error: could not look up ${repo}:${tag}" >&2; exit 1 ;;
    esac
    ;;

  add)
    repo="$1"; from="$2"; to="$3"

    rc=0; src="$(lookup "${repo}" "${from}")" || rc=$?
    if [[ ${rc} -eq 3 ]]; then echo "error: ${repo}:${from} is not in ECR — nothing to name" >&2; exit 1; fi
    [[ ${rc} -eq 0 ]] || exit 1
    digest="$(cut -f1 <<< "${src}")"

    rc=0; dst="$(lookup "${repo}" "${to}")" || rc=$?
    if [[ ${rc} -eq 0 ]]; then
      if [[ "$(cut -f1 <<< "${dst}")" == "${digest}" ]]; then
        result DIGEST "${digest}"
        echo "${repo}:${to} already names this image (${digest})"
        exit 0
      fi
      echo "error: ${repo}:${to} already names a DIFFERENT image ($(cut -f1 <<< "${dst}"))." >&2
      echo "       ECR tags are immutable, so it cannot be moved to ${from} (${digest})." >&2
      exit 1
    fi
    [[ ${rc} -eq 3 ]] || exit 1

    # The manifest exactly as stored. --output text adds one newline, which
    # $(...) strips, and printf '%s' writes none — the bytes ECR hashed.
    get() {
      aws ecr batch-get-image --repository-name "${repo}" --image-ids "imageTag=${from}" \
        --accepted-media-types application/vnd.oci.image.manifest.v1+json \
                               application/vnd.oci.image.index.v1+json \
                               application/vnd.docker.distribution.manifest.v2+json \
                               application/vnd.docker.distribution.manifest.list.v2+json \
        --query "images[0].$1" --output text
    }
    manifest="$(get imageManifest)"
    media="$(get imageManifestMediaType)"
    printf '%s' "${manifest}" > "${TMP}/manifest.json"

    # Checked before the put, not after: a tag ECR accepted on the wrong
    # bytes could never be taken back.
    local_digest="sha256:$(sha256sum "${TMP}/manifest.json" | cut -d' ' -f1)"
    if [[ "${local_digest}" != "${digest}" ]]; then
      echo "error: the manifest read back hashes to ${local_digest}, not ${digest} — not tagging." >&2
      exit 1
    fi

    if ! aws ecr put-image --repository-name "${repo}" --image-tag "${to}" \
           --image-manifest "file://${TMP}/manifest.json" --image-manifest-media-type "${media}" \
           --image-digest "${digest}" --output text --query 'image.imageId.imageDigest' > /dev/null 2> "${TMP}/err"; then
      # Another build may have added the same name a moment ago.
      rc=0; dst="$(lookup "${repo}" "${to}")" || rc=$?
      if [[ ${rc} -ne 0 || "$(cut -f1 <<< "${dst}")" != "${digest}" ]]; then
        cat "${TMP}/err" >&2
        exit 1
      fi
    fi
    result DIGEST "${digest}"
    echo "${repo}:${to} → ${digest}  (same image as ${from})"
    ;;

  *)
    echo "unknown command: ${cmd}" >&2
    exit 1
    ;;
esac
