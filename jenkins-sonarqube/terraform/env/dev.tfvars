# dev — the only environment this stack has.
#
# cost  ~$69/month for the instance, ~$2/month for the volume, ~$3.65 for the
# cost  Elastic IP. No NAT gateway and no load balancer, which is most of what
# cost  a private-subnet design would add.
#
# cost  make pause   stops the instance   → ~$6/month
# cost  make destroy removes everything   → $0

project_name = "ci"
region       = "us-east-1"

# Checked on every plan. Change it if you move accounts on purpose.
aws_account_id = "570417737010"

# ─── Network ─────────────────────────────────────────────────────────────────

vpc_cidr          = "10.20.0.0/16"
availability_zone = "us-east-1a"

# ─── Access ──────────────────────────────────────────────────────────────────
# Your public egress IP. This gates SSH, Jenkins and SonarQube alike.
#   make myip       does this still match?
#   make myip-set   rewrite it to your current one
#
# A stale entry does not error: the security group drops the packets, so the
# browser hangs rather than refusing. 0.0.0.0/0 is rejected by a validation.

ssh_allowed_cidrs = ["27.109.114.247/32"]

ssh_public_key_path  = "~/.ssh/id_ed25519.pub"
ssh_private_key_path = "~/.ssh/id_ed25519"

# ─── Instance ────────────────────────────────────────────────────────────────

instance_type = "m7i-flex.large"
volume_size   = 25
