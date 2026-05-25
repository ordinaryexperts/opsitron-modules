# =============================================================================
# Application Load Balancer
# =============================================================================

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection || local.is_prod

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb"
  })
}

# =============================================================================
# Target Group
# =============================================================================

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Listeners
# =============================================================================

# HTTP listener: always redirects to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-http-listener"
  })
}

# HTTPS listener: uses pre-provisioned ACM certificate
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-https-listener"
  })
}

# =============================================================================
# Stopped-environment intercept
#
# When `enabled = false`, ECS desired_count is 0 → ALB has no healthy targets
# → the default rule returns the bare "503 Service Temporarily Unavailable".
# This rule sits at priority 1 and intercepts all traffic with a friendly
# branded 503 page while the env is stopped. Disappears (count = 0) on Start.
#
# var.stopped_message_html is nullable so wrapper modules can declare an
# optional passthrough without forcing the caller to provide HTML. The local
# below coalesces null to a canned default, so AWS always receives a non-null
# message_body.
# =============================================================================

locals {
  stopped_message_html_default = <<-HTML
    <!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Environment Paused</title><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;padding:0;height:100%;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:#f9fafb;color:#374151}main{min-height:100%;display:flex;align-items:center;justify-content:center;padding:2rem;box-sizing:border-box}.card{max-width:32rem;text-align:center}h1{margin:0 0 1rem;color:#111827;font-size:1.5rem}p{margin:0;line-height:1.6}</style></head><body><main><div class="card"><h1>This environment is paused</h1><p>This deployment is currently stopped for cost savings. It will return when an administrator starts it.</p></div></main></body></html>
  HTML

  stopped_message_html = coalesce(var.stopped_message_html, local.stopped_message_html_default)
}

resource "aws_lb_listener_rule" "stopped" {
  count        = var.enabled ? 0 : 1
  listener_arn = aws_lb_listener.https.arn
  priority     = 1

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/html"
      status_code  = "503"
      message_body = local.stopped_message_html
    }
  }

  condition {
    path_pattern {
      values = [ "/*" ]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-stopped-intercept"
  })
}

# =============================================================================
# Vanity SNI Certificate (added when vanity_acm_certificate_arn is provided)
# =============================================================================

resource "aws_lb_listener_certificate" "vanity" {
  count           = var.vanity_acm_certificate_arn != "" ? 1 : 0
  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = var.vanity_acm_certificate_arn
}

# =============================================================================
# Route53 DNS Record
# =============================================================================

resource "aws_route53_record" "app" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
