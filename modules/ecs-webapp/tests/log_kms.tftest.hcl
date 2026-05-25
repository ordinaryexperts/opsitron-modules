# modules/ecs-webapp/tests/log_kms.tftest.hcl
#
# Plan-only tests for CloudWatch log group KMS encryption and retention default.
mock_provider "aws" {
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
  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/ptest-dev1-alb/1234567890abcdef/abcdef1234567890"
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

run "log_kms_arn_encrypts_all_log_groups" {
  command = plan

  variables {
    log_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/abcd-1234"
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/abcd-1234"
    error_message = "app log group must use the supplied KMS key"
  }
  assert {
    condition     = aws_cloudwatch_log_group.ecs_cluster.kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/abcd-1234"
    error_message = "ecs_cluster log group must use the supplied KMS key"
  }
  assert {
    condition     = aws_cloudwatch_log_group.rds[0].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/abcd-1234"
    error_message = "rds log group must use the supplied KMS key"
  }
  assert {
    condition     = aws_cloudwatch_log_group.worker[0].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/abcd-1234"
    error_message = "worker log group must use the supplied KMS key"
  }
}

run "log_kms_blank_leaves_groups_unencrypted" {
  command = plan

  variables {
    log_kms_key_arn = ""
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.kms_key_id == null
    error_message = "empty log_kms_key_arn must leave app log group unencrypted (kms_key_id null)"
  }
  assert {
    condition     = aws_cloudwatch_log_group.ecs_cluster.kms_key_id == null
    error_message = "empty log_kms_key_arn must leave ecs_cluster log group unencrypted (kms_key_id null)"
  }
  assert {
    condition     = aws_cloudwatch_log_group.rds[0].kms_key_id == null
    error_message = "empty log_kms_key_arn must leave rds log group unencrypted (kms_key_id null)"
  }
  assert {
    condition     = aws_cloudwatch_log_group.worker[0].kms_key_id == null
    error_message = "empty log_kms_key_arn must leave worker log group unencrypted (kms_key_id null)"
  }
}

run "log_retention_defaults_to_365" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == 365
    error_message = "log_retention_days must default to 365"
  }
}
