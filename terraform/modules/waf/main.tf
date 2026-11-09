# WAF module — one web ACL to put in front of a load balancer.
#
# Attaching it is not this module's job. In this platform the ALB belongs to
# the AWS Load Balancer Controller, so the root publishes web_acl_arn to SSM
# and every Ingress in the ALB group carries it
# (alb.ingress.kubernetes.io/wafv2-acl-arn); the controller associates it.
#
# Rules, lowest priority number first — the first that blocks wins:
#
#   10 rate-limit         one IP over rate_limit requests in 5 minutes gets
#                         403 until it slows down. rate_limit_exempt_cidrs are
#                         never counted (the admin IP, so load tests pass).
#   20 ip-reputation      AWS's list of addresses known for bots and attacks
#   30 known-bad-inputs   exploit patterns: Log4j, Spring4Shell, …
#   40 common             OWASP-style: XSS, path traversal, bad bots, …
#                         rules named in count_only_common_rules only COUNT
#   50 sqli               SQL injection
#
# Request logs (enable_logging): see the bottom of this file.
#
# Everything else is allowed. Every rule has CloudWatch metrics and sampled
# requests: WAF console → Web ACLs → <name> → Overview / Sampled requests.
#
# Cost while it exists: ~$5/month for the ACL, $1/month per rule (5),
# $0.60 per million requests.

locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
  name_prefix = "${var.project_name}-${var.environment}"

  # Managed rule groups, in evaluation order after the rate limit.
  managed_rule_groups = [
    { name = "ip-reputation", group = "AWSManagedRulesAmazonIpReputationList", priority = 20, count_only = [] },
    { name = "known-bad-inputs", group = "AWSManagedRulesKnownBadInputsRuleSet", priority = 30, count_only = [] },
    { name = "common", group = "AWSManagedRulesCommonRuleSet", priority = 40, count_only = var.count_only_common_rules },
    { name = "sqli", group = "AWSManagedRulesSQLiRuleSet", priority = 50, count_only = [] },
  ]
}

# ─── Rate-limit exemptions ───────────────────────────────────────────────────
# Always created, possibly empty: the rate rule's scope-down references it, and
# an empty set simply exempts no one.

resource "aws_wafv2_ip_set" "rate_limit_exempt" {
  name               = "${local.name_prefix}-waf-exempt"
  description        = "Never counted by the ${local.name_prefix} WAF rate limit"
  scope              = var.scope
  ip_address_version = "IPV4"
  addresses          = var.rate_limit_exempt_cidrs

  tags = local.common_tags
}

# ─── Web ACL ─────────────────────────────────────────────────────────────────

resource "aws_wafv2_web_acl" "this" {
  name        = "${local.name_prefix}-${var.name_suffix}"
  description = "In front of the ${var.environment} ${var.name_suffix}"
  scope       = var.scope

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 10

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"

        scope_down_statement {
          not_statement {
            statement {
              ip_set_reference_statement {
                arn = aws_wafv2_ip_set.rate_limit_exempt.arn
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = local.managed_rule_groups

    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.value.group

          dynamic "rule_action_override" {
            for_each = rule.value.count_only

            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name_prefix}-${rule.value.name}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-${var.name_suffix}"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-${var.name_suffix}" })
}

# ─── Request logs ────────────────────────────────────────────────────────────
# Every request the ACL saw — client IP, URI, which rule matched, and the
# action — to CloudWatch Logs. WAF only delivers to a log group whose name
# starts with aws-waf-logs-. Credentials are redacted before they are written.
#
#   Logs Insights, on aws-waf-logs-<name>:
#     fields @timestamp, httpRequest.clientIp, httpRequest.uri, terminatingRuleId
#     | filter action = "BLOCK" | sort @timestamp desc

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_logging ? 1 : 0

  name              = "aws-waf-logs-${local.name_prefix}-${var.name_suffix}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# Lets the log delivery service write into that group — and only for this
# account's resources.
resource "aws_cloudwatch_log_resource_policy" "waf" {
  count = var.enable_logging ? 1 : 0

  policy_name = "${local.name_prefix}-${var.name_suffix}-waf-logs"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.waf[0].arn}:*"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*" }
      }
    }]
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.enable_logging ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.waf]
}
