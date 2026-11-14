# prod — the same code, sized to survive things.
#
# cost  ~$420/month (~$14/day) while it exists, before Container Insights usage
# cost  EKS control plane $73 · 3 × t3.medium ~$182 · 3 NAT ~$99 · ALB ~$16
#
# Read this next to dev.tfvars. Every difference is a deliberate answer to
# "what happens when one machine or one datacentre goes away".

project_name = "group-3-devops"
region       = "us-east-1"

aws_account_id = "570417737010"

# ─── Network ─────────────────────────────────────────────────────────────────

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

# One NAT per AZ, ~$33/month each. With a shared one, losing us-east-1a takes
# egress away from every private subnet in the VPC.
single_nat_gateway = false

# Rejected-traffic logs to CloudWatch. Off in dev because it is noise you will
# not read; on here because after an incident it is the only record of what
# was refused and from where.
enable_flow_logs = true

# ─── Cluster ─────────────────────────────────────────────────────────────────

kubernetes_version = "1.36"

# In prod this should be an office range or a VPN egress address, not whatever
# a laptop happens to have today.
#   make myip-set WORKSPACE=prod
api_allowed_cidrs = ["117.20.112.72/32"]

admin_principal_arns = []
team_access          = {}

# ─── Nodes ───────────────────────────────────────────────────────────────────
# One node per AZ at minimum, so losing an AZ leaves two thirds of capacity
# rather than none.

node_instance_types = ["c7i-flex.large"]
node_capacity_type  = "ON_DEMAND"
node_min_size       = 1
node_desired_size   = 2
node_max_size       = 4
node_disk_size      = 50

# ─── Observability ───────────────────────────────────────────────────────────

log_retention_days        = 90
enable_container_insights = true

# ─── DNS and HTTPS ───────────────────────────────────────────────────────────
# Prod owns the apex. The certificate covers devops-selft-learning.xyz and
# *.devops-selft-learning.xyz — argocd.<apex> among them. A www alias would
# also need an Ingress rule for it in the cluster project, so it is not here.

dns_zone_name = "devops-selft-learning.xyz"
site_hostname = "devops-selft-learning.xyz"
site_aliases  = []

# ─── Secrets ─────────────────────────────────────────────────────────────────
# A deleted prod secret stays restorable for a week. dev and uat use 0, so a
# rebuild can reuse the names immediately. Here the names stay reserved for
# that week, so `make plan` restores the secrets before a rebuild needs them.

secret_recovery_window_days = 7

tags = {
  Owner = "learning"
}
