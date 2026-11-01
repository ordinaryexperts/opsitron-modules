# =============================================================================
# SES Domain Identity (conditional on enable_ses)
# Requires domain_name and route53_zone_id to be set.
# =============================================================================

resource "aws_ses_domain_identity" "main" {
  count = var.enable_ses ? 1 : 0

  domain = var.domain_name

  lifecycle {
    precondition {
      condition     = var.domain_name != ""
      error_message = "domain_name is required when enable_ses is true."
    }
    precondition {
      condition     = var.route53_zone_id != ""
      error_message = "route53_zone_id is required when enable_ses is true."
    }
  }
}

# Domain Verification
resource "aws_route53_record" "ses_verification" {
  count = var.enable_ses ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.main[0].verification_token]
}

resource "aws_ses_domain_identity_verification" "main" {
  count = var.enable_ses ? 1 : 0

  domain     = aws_ses_domain_identity.main[0].id
  depends_on = [aws_route53_record.ses_verification]
}

# DKIM
resource "aws_ses_domain_dkim" "main" {
  count = var.enable_ses ? 1 : 0

  domain = aws_ses_domain_identity.main[0].domain
}

resource "aws_route53_record" "ses_dkim" {
  count = var.enable_ses ? 3 : 0

  zone_id = var.route53_zone_id
  name    = "${aws_ses_domain_dkim.main[0].dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.main[0].dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# Mail From Domain
resource "aws_ses_domain_mail_from" "main" {
  count = var.enable_ses ? 1 : 0

  domain           = aws_ses_domain_identity.main[0].domain
  mail_from_domain = "mail.${var.domain_name}"
}

resource "aws_route53_record" "ses_mail_from_mx" {
  count = var.enable_ses ? 1 : 0

  zone_id = var.route53_zone_id
  name    = aws_ses_domain_mail_from.main[0].mail_from_domain
  type    = "MX"
  ttl     = 600
  records = ["10 feedback-smtp.${data.aws_region.current.id}.amazonses.com"]
}

resource "aws_route53_record" "ses_mail_from_spf" {
  count = var.enable_ses ? 1 : 0

  zone_id = var.route53_zone_id
  name    = aws_ses_domain_mail_from.main[0].mail_from_domain
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com ~all"]
}

# DMARC
# DKIM and SPF above already align with the From domain, so a p=none policy is
# enough to produce a DMARC pass, which materially improves inbox placement.
resource "aws_route53_record" "ses_dmarc" {
  count = var.enable_ses ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = ["v=DMARC1; p=none;"]
}

# Configuration Set
resource "aws_ses_configuration_set" "main" {
  count = var.enable_ses ? 1 : 0

  name = local.name_prefix

  reputation_metrics_enabled = true
  sending_enabled            = true

  delivery_options {
    tls_policy = "Require"
  }
}

# =============================================================================
# SES Event Publishing (conditional on enable_ses_event_publishing)
#
# Without an event destination the configuration set above emits bounce,
# complaint and delivery events nowhere. Mailbox providers judge a sending
# domain on its bounce and complaint rates, so an application that cannot see
# those numbers finds out it has a problem only once delivery is already
# failing.
# =============================================================================

locals {
  ses_events_enabled = var.enable_ses && var.enable_ses_event_publishing
}

resource "aws_sns_topic" "ses_events" {
  count = local.ses_events_enabled ? 1 : 0

  name = "${local.name_prefix}-ses-events"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ses-events"
  })
}

# SES publishes as a service principal, so the topic needs a resource policy;
# without it SES drops events silently rather than reporting an error.
# SourceAccount and SourceArn scope the grant to this account's configuration
# set (confused-deputy protection).
resource "aws_sns_topic_policy" "ses_events" {
  count = local.ses_events_enabled ? 1 : 0

  arn = aws_sns_topic.ses_events[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSESPublish"
        Effect = "Allow"
        Principal = {
          Service = "ses.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.ses_events[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
            "AWS:SourceArn"     = "arn:aws:ses:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:configuration-set/${aws_ses_configuration_set.main[0].name}"
          }
        }
      }
    ]
  })
}

# The configuration set above is the v1 resource; the v2 event destination
# resource takes the set by name, so the two compose without migrating it.
resource "aws_sesv2_configuration_set_event_destination" "ses_events" {
  count = local.ses_events_enabled ? 1 : 0

  configuration_set_name = aws_ses_configuration_set.main[0].name
  event_destination_name = "${local.name_prefix}-sns"

  event_destination {
    enabled              = true
    matching_event_types = var.ses_event_types

    sns_destination {
      topic_arn = aws_sns_topic.ses_events[0].arn
    }
  }

  depends_on = [aws_sns_topic_policy.ses_events]
}

# The application's webhook fails closed: it rejects every message, including
# SNS's own subscription confirmation, until the running container has
# AWS_SES_SNS_TOPIC_ARN set to this topic. On a first apply the tasks are still
# on the previous task definition without that variable, so SNS's confirmation
# POST gets a 403 and the endpoint_auto_confirms wait times out - the apply
# fails, and only succeeds on a retry once the service has rolled.
#
# depends_on is what serialises "tasks are running with the new env var" before
# "SNS attempts confirmation": aws_ecs_service.app sets wait_for_steady_state,
# so it does not return until the new task definition is live. Terraform cannot
# infer this - the subscription only references the topic ARN and the domain
# name. Do not remove it as a redundant dependency.
resource "aws_sns_topic_subscription" "ses_events_webhook" {
  count = local.ses_events_enabled && var.ses_event_webhook_path != null ? 1 : 0

  topic_arn              = aws_sns_topic.ses_events[0].arn
  protocol               = "https"
  endpoint               = "https://${var.domain_name}${var.ses_event_webhook_path}"
  endpoint_auto_confirms = true

  depends_on = [aws_ecs_service.app]
}
