# Application secrets — one Secrets Manager secret per team, per environment.
#
#   upskill-devops/dev/api-service   {"DB_PASSWORD": "…", "JWT_SECRET": "…"}
#   upskill-devops/dev/web-service   {…}
#
# Terraform creates the secret and who may read it, never the value: a value
# in Terraform is a value in state. The cluster project writes it
# (make secret-push), and External Secrets copies it into the team's namespace
# as the app-env Secret the services already read with envFrom.
#
#   Secrets Manager ──GetSecretValue──► <cluster>-secrets-<team> role
#                                             ▲ AssumeRole
#                         external-secrets controller (pod identity)
#                                             ▲
#                     SecretStore in namespace <team> names that role
#
# One role per team is the isolation. A team can write an ExternalSecret
# naming another team's secret, but its own SecretStore's role cannot read it.
#
# $0.40 per secret per month.

locals {
  secrets_name_prefix = "${var.project_name}/${local.environment}"
  secrets_role_prefix = "${local.cluster_name}-secrets-"
}

resource "aws_secretsmanager_secret" "team" {
  for_each = toset(var.teams)

  name        = "${local.secrets_name_prefix}/${each.key}"
  description = "Application environment for ${each.key} in ${local.environment}. Value written by `make secret-push` in the cluster project."

  # A deleted secret's name stays reserved for the whole recovery window, so a
  # destroy and re-apply inside it fails on "scheduled for deletion". 0 frees
  # the name at once — and loses the value at once.
  recovery_window_in_days = var.secret_recovery_window_days

  tags = merge(var.tags, { Team = each.key })
}

data "aws_iam_policy_document" "team_secrets_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = [module.eks.pod_identities["external-secrets"].role_arn]
    }
  }
}

resource "aws_iam_role" "team_secrets" {
  for_each = toset(var.teams)

  name               = "${local.secrets_role_prefix}${each.key}"
  assume_role_policy = data.aws_iam_policy_document.team_secrets_trust.json

  tags = merge(var.tags, { Team = each.key })
}

resource "aws_iam_role_policy" "team_secrets" {
  for_each = toset(var.teams)

  name = "read-${each.key}-secret"
  role = aws_iam_role.team_secrets[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = aws_secretsmanager_secret.team[each.key].arn
    }]
  })
}
