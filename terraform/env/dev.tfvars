# dev — where every change lands first. Smallest shape that still runs the
# whole platform: controllers, Argo CD, and every service.
#
# cost  ~$250/month (~$8/day) while it exists — destroy it when not in use
# cost  EKS control plane $73 · 2 × c7i-flex.large ~$124 · NAT ~$33 · ALB ~$16
#
# `environment` is NOT set here. It comes from the workspace name, so the
# file and the state can never disagree about which environment this is.

project_name = "upskill-devops"
region       = "us-east-1"

aws_account_id = "570417737010"

# ─── Network ─────────────────────────────────────────────────────────────────

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# One NAT gateway shared by both AZs. ~$33/month and the single largest
# fixed line after the control plane. If us-east-1a dies, both AZs lose
# egress — the right trade in dev, not in prod.
single_nat_gateway = true
enable_flow_logs   = false

# ─── Cluster ─────────────────────────────────────────────────────────────────

kubernetes_version = "1.36"

# Your public egress IP, as AWS sees it — not a 192.168.x address.
#   make myip     WORKSPACE=dev   does this line still match?
#   make myip-set WORKSPACE=dev   rewrite it to your current one
# A stale entry does not error: the API drops the request and kubectl hangs.
api_allowed_cidrs = ["27.109.114.41/32"]

# Whoever runs the first apply is cluster-admin already. Add teammates here.
admin_principal_arns = []

# Team identities, each scoped to its own namespaces. Empty until the teams
# have IAM roles; see modules/eks/variables.tf for the shape.
team_access = {}

# ─── Nodes ───────────────────────────────────────────────────────────────────
# 29 pods per c7i-flex.large — the VPC CNI gives every pod a VPC address, so
# the network interfaces, not memory, set the ceiling.

node_instance_types = ["c7i-flex.large"]
node_capacity_type  = "ON_DEMAND"
node_min_size       = 1
node_desired_size   = 2
node_max_size       = 4
node_disk_size      = 50

# ─── Observability ───────────────────────────────────────────────────────────

log_retention_days        = 7
enable_container_insights = true

# ─── DNS and HTTPS ───────────────────────────────────────────────────────────
# The zone already exists and is delegated; Terraform only reads it. The
# certificate for dev.<zone> and *.dev.<zone> is issued and DNS-validated by
# this apply.

dns_zone_name = "devops-selft-learning.xyz"
site_hostname = "dev.devops-selft-learning.xyz"
site_aliases  = []

tags = {
  Owner = "learning"
}
