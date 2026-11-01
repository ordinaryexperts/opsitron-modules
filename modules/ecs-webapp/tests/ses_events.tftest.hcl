# modules/ecs-webapp/tests/ses_events.tftest.hcl
#
# Tests for SES event publishing: the SNS topic, its access policy, the
# configuration-set event destination, the optional HTTPS subscription, and the
# AWS_SES_SNS_TOPIC_ARN container environment variable.
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
  # dkim_tokens has to be mocked explicitly: the module indexes three elements
  # out of it for the CNAME records, and the generated default is an empty list.
  mock_resource "aws_ses_domain_dkim" {
    defaults = {
      dkim_tokens = [
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "cccccccccccccccccccccccccccccccc",
      ]
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
  enable_ses          = true
}

# The backwards-compatibility case: every environment already running with
# enable_ses = true must be untouched until it opts in.
run "ses_without_event_publishing_creates_nothing_and_injects_no_topic_arn" {
  command = apply

  assert {
    condition     = length(aws_sns_topic.ses_events) == 0
    error_message = "no SES events topic may be created unless enable_ses_event_publishing = true"
  }

  assert {
    condition     = length(aws_sesv2_configuration_set_event_destination.ses_events) == 0
    error_message = "no configuration set event destination may be created unless enable_ses_event_publishing = true"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.ses_events_webhook) == 0
    error_message = "no webhook subscription may be created unless enable_ses_event_publishing = true"
  }

  assert {
    condition = !can(
      [for e in jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment : e if e.name == "AWS_SES_SNS_TOPIC_ARN"][0]
    )
    error_message = "AWS_SES_SNS_TOPIC_ARN must be absent from the container definition when event publishing is off"
  }

  assert {
    condition = length([
      for e in jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment : e
      if e.name == "AWS_SES_CONFIGURATION_SET"
    ]) == 1
    error_message = "the existing enable_ses environment variables must be unaffected"
  }
}

run "event_publishing_creates_the_topic_and_event_destination" {
  command = apply

  variables {
    enable_ses_event_publishing = true
  }

  assert {
    condition     = aws_sns_topic.ses_events[0].name == "ptest-dev1-ses-events"
    error_message = "the SES events topic must be named off the module name prefix"
  }

  assert {
    condition     = aws_sesv2_configuration_set_event_destination.ses_events[0].configuration_set_name == aws_ses_configuration_set.main[0].name
    error_message = "the event destination must attach to the module's own configuration set"
  }

  assert {
    condition = tolist(aws_sesv2_configuration_set_event_destination.ses_events[0].event_destination[0].matching_event_types) == tolist([
      "BOUNCE", "COMPLAINT", "DELIVERY"
    ])
    error_message = "the event destination must publish the configured event types, defaulting to BOUNCE, COMPLAINT and DELIVERY"
  }

  assert {
    condition     = aws_sesv2_configuration_set_event_destination.ses_events[0].event_destination[0].sns_destination[0].topic_arn == aws_sns_topic.ses_events[0].arn
    error_message = "the event destination must publish to the module's SES events topic"
  }

  assert {
    condition     = length(aws_sns_topic_policy.ses_events) == 1
    error_message = "the topic needs a resource policy or SES silently fails to publish"
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.ses_events[0].policy).Statement[0].Principal.Service == "ses.amazonaws.com"
    error_message = "the topic policy must grant publish rights to the SES service principal"
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.ses_events[0].policy).Statement[0].Action == "SNS:Publish"
    error_message = "the topic policy must grant SNS:Publish"
  }

  # Confused-deputy protection: without these conditions any account's SES
  # could publish to this topic.
  assert {
    condition     = jsondecode(aws_sns_topic_policy.ses_events[0].policy).Statement[0].Condition.StringEquals["AWS:SourceAccount"] == "123456789012"
    error_message = "the topic policy must be scoped to this account"
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.ses_events[0].policy).Statement[0].Condition.StringEquals["AWS:SourceArn"] == "arn:aws:ses:us-east-1:123456789012:configuration-set/ptest-dev1"
    error_message = "the topic policy must be scoped to this module's configuration set"
  }
}

run "event_publishing_injects_the_topic_arn_into_the_containers" {
  command = apply

  variables {
    enable_ses_event_publishing = true
    enable_worker               = true
  }

  assert {
    condition = one([
      for e in jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment : e.value
      if e.name == "AWS_SES_SNS_TOPIC_ARN"
    ]) == aws_sns_topic.ses_events[0].arn
    error_message = "the app container must receive AWS_SES_SNS_TOPIC_ARN set to the SES events topic ARN"
  }

  assert {
    condition = one([
      for e in jsondecode(aws_ecs_task_definition.worker[0].container_definitions)[0].environment : e.value
      if e.name == "AWS_SES_SNS_TOPIC_ARN"
    ]) == aws_sns_topic.ses_events[0].arn
    error_message = "the worker container must receive AWS_SES_SNS_TOPIC_ARN too - the webhook fails closed without it"
  }
}

run "custom_event_types_are_honoured" {
  command = apply

  variables {
    enable_ses_event_publishing = true
    ses_event_types             = ["BOUNCE", "COMPLAINT", "DELIVERY", "DELIVERY_DELAY"]
  }

  assert {
    condition = tolist(aws_sesv2_configuration_set_event_destination.ses_events[0].event_destination[0].matching_event_types) == tolist([
      "BOUNCE", "COMPLAINT", "DELIVERY", "DELIVERY_DELAY"
    ])
    error_message = "ses_event_types must drive the event destination's matching event types"
  }
}

run "null_webhook_path_creates_no_subscription" {
  command = apply

  variables {
    enable_ses_event_publishing = true
  }

  assert {
    condition     = length(aws_sns_topic_subscription.ses_events_webhook) == 0
    error_message = "leaving ses_event_webhook_path null must create the topic only, with no subscription"
  }

  assert {
    condition     = length(aws_sns_topic.ses_events) == 1
    error_message = "the topic must still be created so callers can subscribe to it themselves"
  }
}

run "webhook_path_subscribes_the_application_endpoint" {
  command = apply

  variables {
    enable_ses_event_publishing = true
    ses_event_webhook_path      = "/webhooks/ses"
  }

  assert {
    condition     = aws_sns_topic_subscription.ses_events_webhook[0].endpoint == "https://ptest.example.com/webhooks/ses"
    error_message = "the subscription endpoint must be the webhook path on the application's own domain"
  }

  assert {
    condition     = aws_sns_topic_subscription.ses_events_webhook[0].protocol == "https"
    error_message = "the subscription must use https"
  }

  assert {
    condition     = aws_sns_topic_subscription.ses_events_webhook[0].endpoint_auto_confirms == true
    error_message = "the consumer confirms the subscription itself, so endpoint_auto_confirms must be true"
  }

  assert {
    condition     = aws_sns_topic_subscription.ses_events_webhook[0].topic_arn == aws_sns_topic.ses_events[0].arn
    error_message = "the subscription must attach to the module's SES events topic"
  }
}

run "event_publishing_is_inert_without_ses" {
  command = apply

  variables {
    enable_ses                  = false
    enable_ses_event_publishing = true
    ses_event_webhook_path      = "/webhooks/ses"
  }

  assert {
    condition     = length(aws_sns_topic.ses_events) == 0
    error_message = "no SES events topic may exist when enable_ses = false"
  }

  assert {
    condition     = length(aws_sesv2_configuration_set_event_destination.ses_events) == 0
    error_message = "no event destination may exist when enable_ses = false"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.ses_events_webhook) == 0
    error_message = "no subscription may exist when enable_ses = false"
  }

  assert {
    condition = !can(
      [for e in jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment : e if e.name == "AWS_SES_SNS_TOPIC_ARN"][0]
    )
    error_message = "AWS_SES_SNS_TOPIC_ARN must be absent when enable_ses = false"
  }
}

run "invalid_event_type_is_rejected" {
  command = plan

  variables {
    enable_ses_event_publishing = true
    ses_event_types             = ["BOUNCE", "NOT_AN_EVENT"]
  }

  expect_failures = [
    var.ses_event_types,
  ]
}

run "webhook_path_without_a_leading_slash_is_rejected" {
  command = plan

  variables {
    enable_ses_event_publishing = true
    ses_event_webhook_path      = "webhooks/ses"
  }

  expect_failures = [
    var.ses_event_webhook_path,
  ]
}
