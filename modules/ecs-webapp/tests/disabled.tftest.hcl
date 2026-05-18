# modules/ecs-webapp/tests/disabled.tftest.hcl
#
# Plan-only test for the `enabled = false` power-state contract.
# Verifies that toggling `enabled = false`:
#   - drops app and worker ECS services to desired_count = 0
#   - pins the autoscaling target to min/max capacity = 0
#   - sets Aurora Serverless v2 min_capacity ACU to 0 (cluster auto-pauses)
#   - keeps the RDS cluster, KMS keys, S3 buckets, and other data resources planned
#
# Uses mock_provider so the test runs without AWS credentials or real fixtures.

mock_provider "aws" {
  # Several AWS resources validate the *format* of ARNs they consume from other resources
  # during plan. The default mock provider invents random IDs that don't look like ARNs,
  # so we override the computed attributes for each ARN-producing resource the module wires
  # together. Values are syntactically valid; they don't need to point at anything real.
  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/ptest-dev1-alb/1234567890abcdef"
      dns_name = "ptest-dev1-alb-1234567890.us-east-1.elb.amazonaws.com"
      zone_id  = "Z35SXDOTRQ7X7K"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/ptest-dev1-tg/1234567890abcdef"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/ptest-dev1-policy"
    }
  }
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:ptest-dev1-alerts"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
      key_id = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/ptest-dev1-role"
    }
  }
  mock_resource "aws_ssm_parameter" {
    defaults = {
      arn = "arn:aws:ssm:us-east-1:123456789012:parameter/ptest/dev1/value"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/ptest"
      user_id    = "AIDAEXAMPLE"
    }
  }
  mock_data "aws_region" {
    defaults = {
      id     = "us-east-1"
      name   = "us-east-1"
      region = "us-east-1"
    }
  }
  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "latest"
    }
  }
}

mock_provider "random" {}

variables {
  name                = "ptest"
  vpc_id              = "vpc-1234567890abcdef0"
  public_subnet_ids   = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]
  private_subnet_ids  = ["subnet-ccccccccccccccccc", "subnet-ddddddddddddddddd"]
  database_subnet_ids = ["subnet-eeeeeeeeeeeeeeeee", "subnet-fffffffffffffffff"]
  ecr_repository_url  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/ptest"
  domain_name         = "ptest.example.com"
  route53_zone_id     = "Z000000000000000000000"
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  environment         = "dev1"
  enable_worker       = true
}

run "enabled_true_uses_configured_capacity" {
  command = plan

  variables {
    enabled       = true
    desired_count = 2
    min_capacity  = 2
    max_capacity  = 6
  }

  assert {
    condition     = aws_ecs_service.app.desired_count == 2
    error_message = "When enabled=true, app service should use configured desired_count"
  }

  assert {
    condition     = aws_appautoscaling_target.app.min_capacity == 2 && aws_appautoscaling_target.app.max_capacity == 6
    error_message = "When enabled=true, autoscaling target should use configured min/max capacity"
  }

  assert {
    condition     = aws_ecs_service.worker[0].desired_count == 1
    error_message = "When enabled=true, worker service should use configured worker_desired_count default"
  }

  assert {
    condition     = aws_rds_cluster.main[0].serverlessv2_scaling_configuration[0].min_capacity == 0.5
    error_message = "When enabled=true, Aurora min ACU should match aurora_serverless_min_capacity default of 0.5"
  }
}

run "enabled_false_scales_compute_to_zero" {
  command = plan

  variables {
    enabled       = false
    desired_count = 2
    min_capacity  = 2
    max_capacity  = 6
  }

  assert {
    condition     = aws_ecs_service.app.desired_count == 0
    error_message = "When enabled=false, app service desired_count must be 0"
  }

  assert {
    condition     = aws_appautoscaling_target.app.min_capacity == 0 && aws_appautoscaling_target.app.max_capacity == 0
    error_message = "When enabled=false, autoscaling target min and max capacity must both be 0"
  }

  assert {
    condition     = aws_ecs_service.worker[0].desired_count == 0
    error_message = "When enabled=false, worker service desired_count must be 0"
  }

  assert {
    condition     = aws_rds_cluster.main[0].serverlessv2_scaling_configuration[0].min_capacity == 0
    error_message = "When enabled=false, Aurora Serverless min_capacity must be 0 so the cluster auto-pauses"
  }

  # Data resources remain planned even when enabled=false — toggling back to true
  # restores the environment without recreating storage.
  assert {
    condition     = length(aws_rds_cluster.main) == 1
    error_message = "RDS cluster must still be planned when enabled=false (data preservation)"
  }

  assert {
    condition     = length(aws_kms_key.rds) == 1
    error_message = "RDS KMS key must still be planned when enabled=false (data preservation)"
  }

  assert {
    condition     = length(aws_ssm_parameter.db_password) == 1
    error_message = "DB password SSM parameter must still be planned when enabled=false (data preservation)"
  }
}
