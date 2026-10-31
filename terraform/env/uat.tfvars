# uat — prod-shaped, dev-sized. Where a release is accepted before it ships.
#
# cost  ~$290/month (~$9.50/day) while it exists
# cost  EKS control plane $73 · 2 × t3.large ~$121 · 2 NAT ~$66 · ALB ~$16
#
# `environment` is NOT set here. It comes from the workspace name, so the
# file and the state can never disagree about which environment this is.

project_name = "upskill-devops"
region       = "us-east-1"

aws_account_id = "570417737010"

# ─── Network ─────────────────────────────────────────────────────────────────

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# One NAT per AZ, as in prod. UAT is where an AZ-failure drill is rehearsed,
# and a shared NAT would make that drill test the wrong thing.
single_nat_gateway = false
enable_flow_logs   = false

# ─── Cluster ─────────────────────────────────────────────────────────────────

kubernetes_version = "1.36"

#   make myip-set WORKSPACE=uat   rewrite it to your current one
api_allowed_cidrs = ["27.109.114.159/32"]

admin_principal_arns = []
team_access          = {}

# ─── Nodes ───────────────────────────────────────────────────────────────────

node_instance_types = ["t3.large"]
node_capacity_type  = "ON_DEMAND"
node_min_size       = 2
node_desired_size   = 2
node_max_size       = 4
node_disk_size      = 50

# ─── Observability ───────────────────────────────────────────────────────────

log_retention_days        = 14
enable_container_insights = false

# ─── DNS and HTTPS ───────────────────────────────────────────────────────────

dns_zone_name = "devops-selft-learning.xyz"
site_hostname = "uat.devops-selft-learning.xyz"
site_aliases  = []

tags = {
  Owner = "learning"
}
