#!/usr/bin/env bash
#
# Find what would stop `make up`, before it spends any time or money.
#
#   scripts/preflight.sh <workspace>
#
# Each of these otherwise fails late. An instance type the account's plan
# refuses is the worst: the node group sits in CREATING for 20 minutes with no
# error, and then has to be deleted before the next attempt.
#
# Reads only. Every check runs, so one pass reports everything to fix.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${1:-}"
REGION="us-east-1"

failed=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; shift; printf '        %s\n' "$@"; failed=1; }

vars="${ROOT}/terraform/env/${WORKSPACE}.tfvars"
if [[ -z "${WORKSPACE}" || ! -f "${vars}" ]]; then
  echo "error: name an environment: make up WORKSPACE=<env>" >&2
  echo "       environments: $(ls "${ROOT}"/terraform/env/*.tfvars | xargs -n1 basename | sed 's/.tfvars//' | tr '\n' ' ')" >&2
  exit 1
fi

value() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "${vars}" | head -1; }

echo "==> ${WORKSPACE}"

# ─── This machine ────────────────────────────────────────────────────────────

if docker info >/dev/null 2>&1; then ok "docker is running (Helm runs in a container)"
else fail "docker is not running" "Helm runs in a container, so the cluster half of make up needs it."; fi

if [[ -d "${ROOT}/terraform/.terraform" ]]; then ok "terraform is initialised"
else fail "terraform is not initialised" "make -C terraform init"; fi

# ─── The account ─────────────────────────────────────────────────────────────

expected="$(value aws_account_id | tr -d '"')"
actual="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
if [[ -z "${actual}" ]]; then
  fail "no working AWS credentials" "aws sts get-caller-identity"
elif [[ -n "${expected}" && "${expected}" != "${actual}" ]]; then
  fail "credentials point at ${actual}, ${WORKSPACE} expects ${expected}"
else
  ok "AWS account ${actual}"
fi

# Only a FREE plan restricts instance types. A paid account has no plan state
# to read, so a failure here means there is nothing to check.
types="$(value node_instance_types | tr -d '[]" ' | tr ',' ' ')"
plan="$(aws freetier get-account-plan-state --region "${REGION}" --query accountPlanType --output text 2>/dev/null || true)"
if [[ "${plan}" == "FREE" ]]; then
  for t in ${types}; do
    eligible="$(aws ec2 describe-instance-types --region "${REGION}" --instance-types "${t}" \
      --query 'InstanceTypes[0].FreeTierEligible' --output text 2>/dev/null || true)"
    if [[ "${eligible}" == "True" ]]; then ok "${t} can launch on the Free plan"
    else fail "${t} cannot launch on the Free plan" \
      "The node group would wait 20 minutes for nodes that never start." \
      "Set node_instance_types in terraform/env/${WORKSPACE}.tfvars to one of:" \
      "m7i-flex.large (2 vCPU, 8 GiB)   c7i-flex.large (2 vCPU, 4 GiB)"; fi
  done
else
  ok "instance types: ${types}"
fi

# Each NAT gateway needs an address, and addresses this environment already
# holds are not new ones. ServiceManaged leaves out the ALB's, which are listed
# here but do not count against the quota.
if [[ "$(value single_nat_gateway)" == "true" ]]; then
  need=1
else
  need="$(value availability_zones | tr -cd ',' | wc -c)"; need=$((need + 1))
fi
held="$(aws ec2 describe-addresses --region "${REGION}" \
  --query "length(Addresses[?!ServiceManaged && Tags[?Key=='Environment' && Value=='${WORKSPACE}']])" --output text 2>/dev/null || echo 0)"
used="$(aws ec2 describe-addresses --region "${REGION}" \
  --query 'length(Addresses[?!ServiceManaged])' --output text 2>/dev/null || echo 0)"
limit="$(aws service-quotas get-service-quota --region "${REGION}" --service-code ec2 --quota-code L-0263D0A3 \
  --query 'Quota.Value' --output text 2>/dev/null || echo 5)"
limit="${limit%.*}"
others=$((used - held))
if (( others + need <= limit )); then
  ok "addresses: needs ${need}, ${others} used elsewhere, limit ${limit}"
else
  fail "not enough addresses: needs ${need}, ${others} used elsewhere, limit ${limit}" \
    "Destroy another environment first, or set single_nat_gateway = true in" \
    "terraform/env/${WORKSPACE}.tfvars."
fi

# ─── Application values ──────────────────────────────────────────────────────
# Without these the secrets stay empty, the API pods cannot start, and Helm
# times out five minutes later saying only "context deadline exceeded".

for dir in "${ROOT}"/cluster/helm/values/*/; do
  team="$(basename "${dir}")"
  if [[ -f "${ROOT}/cluster/helm/env/${WORKSPACE}.${team}.env" || -f "${ROOT}/cluster/helm/env/${WORKSPACE}.env" ]]; then
    ok "values for ${team}"
  else
    fail "no values for ${team}" \
      "cp cluster/helm/env/dev.env cluster/helm/env/${WORKSPACE}.env" \
      "Then set DATABASE_URL and new JWT secrets (openssl rand -hex 32) for ${WORKSPACE}."
  fi
done

echo
if [[ "${failed}" -ne 0 ]]; then
  echo "Nothing was changed. Fix the FAIL lines above, then run it again."
  exit 1
fi
echo "All clear."
