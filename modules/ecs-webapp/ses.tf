# =============================================================================
# SES Domain Identity (conditional on enable_ses)
# =============================================================================

resource "aws_ses_domain_identity" "main" {
  count = var.enable_ses ? 1 : 0

  domain = var.domain_name
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
