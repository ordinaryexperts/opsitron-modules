# modules/ecs-webapp/tests/worker_stop_timeout.tftest.hcl
#
# Tests for worker_stop_timeout, which sets stopTimeout on the worker container
# so job runners can drain in-flight work between SIGTERM and SIGKILL.
#
# The container_definitions assertions run against a mocked apply rather than a
# plan: the JSON embeds computed attributes (SSM secret ARNs, RDS endpoints)
# that mock_provider only fills in at apply time, leaving the whole encoded
# string unknown during plan.
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

run "worker_stop_timeout_sets_container_stop_timeout" {
  command = apply

  variables {
    worker_stop_timeout = 120
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.worker[0].container_definitions)[0].stopTimeout == 120
    error_message = "worker_stop_timeout must set stopTimeout on the worker container definition"
  }
}

run "worker_stop_timeout_null_omits_the_field" {
  command = apply

  assert {
    condition     = !can(jsondecode(aws_ecs_task_definition.worker[0].container_definitions)[0].stopTimeout)
    error_message = "unset worker_stop_timeout must omit stopTimeout entirely so ECS applies its 30-second default"
  }
}

run "worker_stop_timeout_rejects_values_above_the_fargate_maximum" {
  command = plan

  variables {
    worker_stop_timeout = 300
  }

  expect_failures = [
    var.worker_stop_timeout,
  ]
}

run "worker_stop_timeout_rejects_values_below_the_minimum" {
  command = plan

  variables {
    worker_stop_timeout = 1
  }

  expect_failures = [
    var.worker_stop_timeout,
  ]
}
