# Audit module — who did what in this AWS account, kept, and the few events
# that should tell a person straight away. One per account (global/), not per
# environment: CloudTrail sees every region and every environment at once.
#
#   CloudTrail trail   every management API call, all regions → S3 (kept
#                      trail_retention_days, digest-signed so tampering shows)
#                      and → CloudWatch Logs (kept cloudwatch_retention_days,
#                      for Logs Insights queries and the alarms below)
#   security alarms    root account used · console login failed · console
#                      login without MFA · IAM policy changed · API calls
#                      denied · CloudTrail itself changed
#
# The alarms only NOTIFY on entering ALARM, not on returning to OK: one email
# per incident, not two.

locals {
  common_tags = merge(
    {
      Project   = var.project_name
      ManagedBy = "terraform"
    },
    var.tags
  )
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  trail_name = "${var.project_name}-audit"
  # Built, not read from the trail, because the bucket policy must name it
  # before the trail can exist.
  trail_arn = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"

  alarm_actions = var.alarm_topic_arn == null ? [] : [var.alarm_topic_arn]

  # CIS AWS Foundations Benchmark, section "Monitoring" — the patterns are the
  # benchmark's own.
  security_events = {
    root-account-used = {
      description = "The root user made an API call or signed in. Root should be locked away; use an IAM identity."
      pattern     = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
      threshold   = 1
    }
    console-login-failed = {
      description = "Console sign-in failures — someone guessing a password."
      pattern     = "{ ($.eventName = ConsoleLogin) && ($.errorMessage = \"Failed authentication\") }"
      threshold   = 3
    }
    console-login-without-mfa = {
      description = "An IAM user signed in to the console without MFA."
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
      threshold   = 1
    }
    iam-policy-changed = {
      description = "An IAM policy was created, changed, attached or detached."
      pattern     = "{ ($.eventName=DeleteGroupPolicy) || ($.eventName=DeleteRolePolicy) || ($.eventName=DeleteUserPolicy) || ($.eventName=PutGroupPolicy) || ($.eventName=PutRolePolicy) || ($.eventName=PutUserPolicy) || ($.eventName=CreatePolicy) || ($.eventName=DeletePolicy) || ($.eventName=CreatePolicyVersion) || ($.eventName=DeletePolicyVersion) || ($.eventName=AttachRolePolicy) || ($.eventName=DetachRolePolicy) || ($.eventName=AttachUserPolicy) || ($.eventName=DetachUserPolicy) || ($.eventName=AttachGroupPolicy) || ($.eventName=DetachGroupPolicy) }"
      threshold   = 1
    }
    api-calls-denied = {
      description = "Many API calls were denied — a misconfigured role, or someone probing what a credential can do."
      pattern     = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
      threshold   = var.denied_calls_threshold
    }
    cloudtrail-changed = {
      description = "A CloudTrail trail was created, changed, stopped or deleted — the audit log itself."
      pattern     = "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }"
      threshold   = 1
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ─── S3: the long-term record ────────────────────────────────────────────────

resource "aws_s3_bucket" "trail" {
  bucket        = "${var.project_name}-cloudtrail-${local.account_id}"
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, { Name = "${var.project_name}-cloudtrail" })
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = var.trail_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}

# Only this account's trail may write, and only into its own prefix.
resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.trail]
}

# ─── CloudWatch Logs: the searchable copy ────────────────────────────────────

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/${var.project_name}/cloudtrail"
  retention_in_days = var.cloudwatch_retention_days

  tags = local.common_tags
}

resource "aws_iam_role" "trail_to_logs" {
  name = "${var.project_name}-cloudtrail-to-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "trail_to_logs" {
  name = "write-trail-log-group"
  role = aws_iam_role.trail_to_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

# ─── The trail ───────────────────────────────────────────────────────────────

resource "aws_cloudtrail" "this" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.trail.id

  is_multi_region_trail         = true
  include_global_service_events = true # IAM, STS, CloudFront — logged in us-east-1
  enable_log_file_validation    = true # digest files: `aws cloudtrail validate-logs` proves nothing was edited

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_to_logs.arn

  tags = local.common_tags

  depends_on = [aws_s3_bucket_policy.trail, aws_iam_role_policy.trail_to_logs]
}

# ─── Security alarms ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_metric_filter" "security" {
  for_each = local.security_events

  name           = each.key
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.key
    namespace     = "${var.project_name}/Security"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "security" {
  for_each = local.security_events

  alarm_name        = "${var.project_name}-security-${each.key}"
  alarm_description = "${each.value.description} Who and from where: Logs Insights on /${var.project_name}/cloudtrail, or CloudTrail → Event history."

  namespace   = "${var.project_name}/Security"
  metric_name = each.key
  statistic   = "Sum"
  period      = 300

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = each.value.threshold
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions

  tags = local.common_tags

  depends_on = [aws_cloudwatch_log_metric_filter.security]
}
