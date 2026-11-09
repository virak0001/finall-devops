# One EC2 instance running Jenkins and SonarQube in Docker.
#
#   make apply     the VPC, the instance, the address
#   make deploy    docker compose up, over SSH
#   make url       where to point a browser
#
# Deliberately small: a public subnet, no NAT gateway, no load balancer. Both
# services need inbound access anyway, so a private subnet would mean paying
# $33/month for a NAT gateway and $16/month for a load balancer to reach a box
# that only you use. The security group is the boundary instead — nothing is
# open to the internet, only to the addresses in ssh_allowed_cidrs.

terraform {
  required_version = ">= 1.10.0" # S3-native state locking (use_lockfile)

  # State lives in the platform's state bucket, not on one laptop, so anyone
  # on the team can plan and apply. Bucket, key and locking come from
  # backend.hcl — `make init` passes it.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = terraform.workspace
      ManagedBy   = "terraform"
      Repository  = "jenkins+sonarqube"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${terraform.workspace}"

  # Both services and SSH, from the same allowlist. A separate variable per
  # port would let them drift apart, and there is no reason for the Jenkins UI
  # to be reachable from somewhere SSH is not.
  ports = {
    ssh       = 22
    jenkins   = 8080
    sonarqube = 9000
  }
}

# Changing AWS credentials does not fail — it succeeds against the wrong
# account, finds none of the resources in state, and builds a second copy of
# everything while the first keeps billing. This is the check.
resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition = (
        var.aws_account_id == null ||
        var.aws_account_id == data.aws_caller_identity.current.account_id
      )
      error_message = <<-ERR
        Wrong AWS account.

          credentials point at   ${data.aws_caller_identity.current.account_id}
          this stack expects     ${coalesce(var.aws_account_id, "(unset)")}

            aws sts get-caller-identity --query Account --output text
      ERR
    }
  }
}

# ─── Network ─────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone = var.availability_zone

  # The Elastic IP is what you actually connect to; this only matters for the
  # brief window before it is associated.
  map_public_ip_on_launch = true

  tags = { Name = "${local.name_prefix}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ─── Security ────────────────────────────────────────────────────────────────

resource "aws_security_group" "ci" {
  name        = "${local.name_prefix}-sg"
  description = "Jenkins, SonarQube and SSH, from the allowlist only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# One rule per port per CIDR. Written out rather than a single rule with a port
# range, so `aws ec2 describe-security-group-rules` says which service each
# rule is for when you are trying to work out why something is unreachable.
resource "aws_vpc_security_group_ingress_rule" "allowed" {
  for_each = {
    for pair in setproduct(keys(local.ports), var.ssh_allowed_cidrs) :
    "${pair[0]}-${pair[1]}" => { service = pair[0], cidr = pair[1] }
  }

  security_group_id = aws_security_group.ci.id
  description       = "${each.value.service} from ${each.value.cidr}"
  cidr_ipv4         = each.value.cidr
  from_port         = local.ports[each.value.service]
  to_port           = local.ports[each.value.service]
  ip_protocol       = "tcp"
}

# GitHub's webhook deliveries, to Jenkins only. A push or pull request on a
# service repo is POSTed to http://<this address>:8080/github-webhook/ and
# starts that repo's multibranch job — without this, Jenkins would only notice
# a push on its next periodic scan.
#
# Jenkins' port alone, from GitHub's published webhook ranges alone. Each
# delivery is signed with the shared secret in docker/.env, and Jenkins drops
# one that does not verify, so an address in these ranges is not enough to
# start a build.
resource "aws_vpc_security_group_ingress_rule" "github_webhooks" {
  for_each = toset(var.github_hook_cidrs)

  security_group_id = aws_security_group.ci.id
  description       = "GitHub webhooks from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = local.ports.jenkins
  to_port           = local.ports.jenkins
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.ci.id
  description       = "Docker pulls, plugin downloads, apt"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ─── IAM (ECR push) ────────────────────────────────────────────────────────────

# Lets the aws-cli sibling containers the pipelines run authenticate via
# instance metadata instead of a long-lived access key sitting in a Jenkins
# credential. Needs the hop-limit bump on aws_instance.ci below —
# a container is one hop further from 169.254.169.254 than the host itself.
data "aws_iam_policy_document" "ci_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${local.name_prefix}-ci-role"
  assume_role_policy = data.aws_iam_policy_document.ci_assume.json
}

data "aws_iam_policy_document" "ci_ecr" {
  # GetAuthorizationToken has no resource-level permissions in IAM — it is
  # always "*", regardless of which repository is pushed to afterwards.
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push, and look up whether a tag already exists (the pipeline skips a
  # rebuild when it does, and the promote job refuses a tag that does not).
  #
  # No ecr:CreateRepository. The repositories are Terraform's
  # (dev-finall/terraform/global); a pipeline that could create its own would
  # make one nobody manages the moment a service name was mistyped.
  statement {
    sid = "ECRPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = ["arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/upskill-devops/*"]
  }

  # The deployment history: one JSON event per deploy, promotion, rollback or
  # failed build (shared-library/vars/recordDeployment.groovy). The log group
  # itself is dev-finall/terraform/global's.
  statement {
    sid = "DeploymentRecords"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${var.deployments_log_group}",
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${var.deployments_log_group}:*",
    ]
  }
}

resource "aws_iam_role_policy" "ci_ecr" {
  name   = "${local.name_prefix}-ecr-push"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_ecr.json
}

resource "aws_iam_instance_profile" "ci" {
  name = "${local.name_prefix}-ci-profile"
  role = aws_iam_role.ci.name
}

# ─── Instance ────────────────────────────────────────────────────────────────

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name = "name"
    # gp3 images exist for 24.04; 22.04 is published only under hvm-ssd, so the
    # storage path in this pattern is tied to the release.
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "ci" {
  key_name   = "${local.name_prefix}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_instance" "ci" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ci.id]
  key_name               = aws_key_pair.ci.key_name
  iam_instance_profile   = aws_iam_instance_profile.ci.name
  user_data              = local.cloud_config

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2 # containers are one hop further out
  }

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${local.name_prefix}-ci" }

  # user_data changes only take effect on a new instance, and rebuilding this
  # box means losing Jenkins jobs and SonarQube history. Bootstrap is
  # deliberately minimal for the same reason: everything that changes lives in
  # docker/, applied by `make deploy`.
  lifecycle {
    ignore_changes = [ami]
  }
}

# Static, so stopping the instance to save money does not change the address —
# and so Jenkins' configured URL and SonarQube's webhook stay correct.
resource "aws_eip" "ci" {
  instance = aws_instance.ci.id
  domain   = "vpc"
  tags     = { Name = "${local.name_prefix}-eip" }

  depends_on = [aws_internet_gateway.main]
}

locals {
  # Only what must happen before Docker can run. The compose file itself is
  # copied by `make deploy`, so changing it never means rebuilding the box.
  cloud_config = <<-CLOUDINIT
    #cloud-config
    package_update: true
    packages:
      - ca-certificates
      - curl
      - gnupg

    write_files:
      # SonarQube embeds Elasticsearch, which refuses to start below this and
      # reports it as a bootstrap check failure inside the container log —
      # nothing in `docker ps` explains why the container keeps restarting.
      # This is the single most common way a SonarQube container fails.
      - path: /etc/sysctl.d/99-sonarqube.conf
        content: |
          vm.max_map_count=262144
          fs.file-max=131072

      # Elasticsearch also wants file descriptors and threads well above the
      # container default. Set on the daemon so every container inherits it.
      - path: /etc/docker/daemon.json
        content: |
          {
            "default-ulimits": {
              "nofile": { "Name": "nofile", "Soft": 131072, "Hard": 131072 },
              "nproc":  { "Name": "nproc",  "Soft": 8192,   "Hard": 8192 }
            },
            "log-driver": "json-file",
            "log-opts": { "max-size": "10m", "max-file": "3" }
          }

    runcmd:
      - sysctl --system
      - install -m 0755 -d /etc/apt/keyrings
      - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
      - chmod a+r /etc/apt/keyrings/docker.asc
      - echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list
      - apt-get update
      - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      - usermod -aG docker ubuntu
      - systemctl enable --now docker
      - mkdir -p /opt/ci
      - chown ubuntu:ubuntu /opt/ci
      # A marker `make deploy` waits for. Without it, deploy races cloud-init
      # and fails on a docker binary that is not installed yet.
      - touch /opt/ci/.bootstrap-complete
  CLOUDINIT
}
