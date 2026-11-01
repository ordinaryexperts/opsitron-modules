# modules/ecs-webapp/tests/database_tags.tftest.hcl
#
# Tests for database_tags, which adds caller-supplied tags to the Aurora
# cluster and its instances only, and for the rds_cluster_arn output.
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

run "database_tags_default_leaves_rds_tags_unchanged" {
  command = apply

  assert {
    condition     = !contains(keys(aws_rds_cluster.main[0].tags), "Backup")
    error_message = "no extra tags may be added to the cluster when database_tags is left empty"
  }

  assert {
    condition     = aws_rds_cluster.main[0].tags["Name"] == "ptest-dev1-cluster" && aws_rds_cluster.main[0].tags["Engine"] == "Aurora Serverless v2"
    error_message = "the cluster must keep its Name and Engine tags"
  }
}

run "database_tags_apply_to_cluster_and_instances" {
  command = apply

  variables {
    database_tags = {
      Backup = "daily"
    }
  }

  assert {
    condition     = aws_rds_cluster.main[0].tags["Backup"] == "daily"
    error_message = "database_tags must be applied to the Aurora cluster"
  }

  assert {
    condition     = alltrue([for i in aws_rds_cluster_instance.main : i.tags["Backup"] == "daily"])
    error_message = "database_tags must be applied to every Aurora cluster instance"
  }

  assert {
    condition     = !contains(keys(aws_db_subnet_group.main[0].tags), "Backup")
    error_message = "database_tags must be scoped to the cluster and instances, not other RDS resources"
  }
}

run "database_tags_cannot_override_name_or_engine" {
  command = apply

  variables {
    database_tags = {
      Name   = "override"
      Engine = "override"
    }
  }

  assert {
    condition     = aws_rds_cluster.main[0].tags["Name"] == "ptest-dev1-cluster" && aws_rds_cluster.main[0].tags["Engine"] == "Aurora Serverless v2"
    error_message = "the module's Name and Engine tags must win over database_tags on the cluster"
  }

  assert {
    condition     = aws_rds_cluster_instance.main[0].tags["Name"] == "ptest-dev1-db-0"
    error_message = "the module's Name tag must win over database_tags on the instances"
  }
}

run "rds_cluster_arn_output_is_the_cluster_arn" {
  command = apply

  assert {
    condition     = output.rds_cluster_arn == aws_rds_cluster.main[0].arn
    error_message = "rds_cluster_arn must expose the Aurora cluster ARN"
  }
}

run "rds_cluster_arn_is_null_when_rds_disabled" {
  command = apply

  variables {
    enable_rds = false
  }

  assert {
    condition     = output.rds_cluster_arn == null
    error_message = "rds_cluster_arn must be null when enable_rds = false"
  }
}
