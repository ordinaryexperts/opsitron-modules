# Changelog

All notable changes to this module are documented in this file.

## [2.13.0] - 2026-10-31

### Added
- `enable_ses_event_publishing` variable (default `false`). When `enable_ses = true` the module already creates the domain identity, DKIM, MAIL FROM, DMARC and a configuration set with reputation metrics — but it created no event destination, so the configuration set emitted bounce, complaint and delivery events nowhere. Mailbox providers decide whether a sending domain keeps working based on its bounce and complaint rates, and every environment deployed with `enable_ses = true` has had those numbers invisible to the application: a complaint rate can climb for weeks with nobody aware until delivery is already failing. Setting this to `true` creates an SNS topic (`${name_prefix}-ses-events`), a topic policy granting `SNS:Publish` to `ses.amazonaws.com` scoped by `AWS:SourceAccount` and the configuration set's `AWS:SourceArn` (without the policy SES drops events silently rather than erroring), and a `aws_sesv2_configuration_set_event_destination` attached to the existing v1 configuration set by name. **Existing environments are unchanged until they opt in** — with the variable left at `false` no new resources are created and no new environment variable is injected.
- `ses_event_types` variable (default `["BOUNCE", "COMPLAINT", "DELIVERY"]`), the event types published to the topic. `DELIVERY` is in the default deliberately: bounce and complaint rates are fractions of *delivered* mail, which is the denominator mailbox providers and the SES reputation dashboard use, so publishing only `BOUNCE` and `COMPLAINT` leaves those rates uncomputable rather than merely approximate. Validated against the SES v2 event-type list.
- `ses_event_webhook_path` variable (default `null`). When set (e.g. `"/webhooks/ses"`), the module subscribes `https://${domain_name}${path}` to the events topic with `endpoint_auto_confirms = true`. Left `null`, the module creates the topic only and callers wire their own subscriptions from the new `ses_events_topic_arn` output. The subscription carries an explicit `depends_on = [aws_ecs_service.app]`: the consumer endpoint is expected to fail closed and reject every message — including SNS's own subscription confirmation — until the running container has `AWS_SES_SNS_TOPIC_ARN` set, so without that ordering the first apply creates the subscription while tasks are still on the previous task definition, the confirmation POST gets a 403, the auto-confirm wait times out and the apply fails, succeeding only on a retry once the service has rolled. `aws_ecs_service.app` sets `wait_for_steady_state`, so depending on it genuinely serialises "tasks are live with the new env var" before "SNS attempts confirmation". Terraform cannot infer this ordering — the subscription only references the topic ARN and the domain name. One consequence: the first apply that enables a webhook subscription needs `enabled = true`, since a paused environment has no running task to confirm it.
- `AWS_SES_SNS_TOPIC_ARN` environment variable, injected into the app and worker containers only when event publishing is on. Consumers should verify the SNS signature *and* compare the message's `TopicArn` against this value: a signature alone is not authentication, because every AWS account signs with the same regional certificates, so signature-only verification would let any AWS customer subscribe the endpoint to a topic of their own and publish fabricated bounces and complaints.
- `ses_events_topic_arn` output — the SNS topic ARN (`null` unless event publishing is enabled), for callers subscribing consumers outside the module.
- `database_tags` variable (`map(string)`, default `{}`). Tags merged onto the Aurora cluster and its instances only, for example backup-selection or data-classification tags that should not spread to every resource in the module. The module's own `Name` and `Engine` tags take precedence. With the default empty map, existing clusters see no tag changes.
- `rds_cluster_arn` output: the Aurora cluster ARN (`null` when `enable_rds = false`), for wiring AWS Backup plans, IAM policies and similar resources outside the module.

## [2.12.0] - 2026-08-15

### Added
- `worker_stop_timeout` variable (default `null`). Sets `stopTimeout` on the worker container definition, controlling how long ECS waits after SIGTERM before SIGKILL. Job runners like Solid Queue drain in-flight work in that window; at the ECS default of 30 seconds a longer-running job is killed mid-flight and recorded as a process-exit failure that `retry_on` cannot catch, because the error is raised by the supervisor rather than inside the job. Valid range is 2-120 (the Fargate maximum); leaving it `null` omits the field entirely, so existing task definitions are unchanged and keep the 30-second ECS default.

## [2.11.0] - 2026-07-25

### Added
- `ecs_worker_service_name` SSM parameter (`${ssm_prefix}/ecs-worker-service-name`), published only when `enable_worker = true`, plus a matching `ssm_ecs_worker_service_name_param` output. The generated container-deploy workflow reads this to roll the worker service onto the same image as the web service. Previously only the web service name was published (`ecs-service-name`), so deploys updated the web service while the worker stayed pinned to whatever image the last `terraform apply` baked in, drifting behind on every deploy. Existing environments must re-apply once to publish the new parameter; the deploy workflow treats its absence as "no worker" and skips cleanly.

### Changed
- `postgres_version` default bumped `17.4` → `17.7` to match the minor version AWS has already auto-applied to existing Aurora clusters.

### Fixed
- Disable AWS-driven Aurora minor-version auto-upgrades (`auto_minor_version_upgrade = false` on the cluster instance). AWS was auto-bumping the instance minor version (e.g. `17.4` → `17.7`); terraform then tried to "downgrade" `engine_version` back to the pinned value on the next unrelated apply and AWS rejected it (`InvalidParameterCombination`), blocking all applies until the drift was reconciled. Minor version upgrades are now explicit, reviewed changes to `var.postgres_version`.

## [2.10.1] - 2026-05-25

### Fixed
- `stopped_message_html` is now nullable (`default = null`) so wrapper modules can declare an optional passthrough without forcing callers to provide HTML. Previously, a wrapper that forwarded an unset value (`stopped_message_html = var.stopped_message_html`) would propagate `null` into ecs-webapp — HCL treats an explicit `null` argument as overriding the variable's default, so the validation block ran `length(null)` and plan failed with "Invalid function argument". The canned default HTML now lives in `local.stopped_message_html_default` and is selected via `coalesce()` so AWS always receives a non-null `message_body`. The validation short-circuits on null and continues to enforce the 1024-byte cap on non-null values.

## [2.10.0] - 2026-05-25

### Added
- Friendly stopped-environment ALB intercept. When `enabled = false`, the module now adds an `aws_lb_listener_rule` at priority 1 that returns an HTTP 503 with a branded "This environment is paused" HTML page, intercepting traffic that would otherwise hit the bare ALB default 503 (no healthy targets). The rule is removed automatically on `enabled = true`. Override the body via `stopped_message_html` (max 1024 bytes — ALB fixed-response limit).

## [2.9.0] - 2026-05-22

- DMARC support when `enable_ses = true`

## [2.8.0] - 2026-05-20

### Added
- `log_kms_key_arn` variable (default `""`). When set to a KMS key ARN, all four CloudWatch log groups created by this module (`ecs_cluster`, `app`, `rds`, `worker`) will have `kms_key_id` set to that ARN. When left empty (the default), no `kms_key_id` is set and log groups use the default AWS-managed encryption. The caller is responsible for granting the CloudWatch Logs service principal (`logs.<region>.amazonaws.com`) usage of the key in the key policy.

### Changed
- `log_retention_days` default changed from `30` to `365` to align with the LZA org-wide CloudWatch retention standard. **Callers that do not pin this variable will move to 365-day retention on the next apply.** Set `log_retention_days = 30` (or any other value) explicitly if you need to preserve the previous behavior.

## [2.7.0] - 2026-05-17

### Added
- `enabled` variable (default `true`) for the Opsitron environment stop/start feature. When set to `false`, the app and worker ECS services drop to `desired_count = 0`, the autoscaling target is pinned to `min_capacity = max_capacity = 0`, and Aurora Serverless v2's `min_capacity` ACU is overridden to `0` so the cluster auto-pauses. All data resources (RDS cluster, snapshots, parameter groups, KMS keys, S3 buckets, SSM parameters, IAM roles) remain in state untouched, so toggling `enabled = true` brings the environment back online with original sizing on the next apply.

## [2.6.0] - 2026-05-17

### Added
- When `enable_ses = true`, the module now injects two environment variables into the app and worker tasks: `MAIL_FROM = "no-reply@${var.domain_name}"` (sensible default for ActionMailer's `default from:`; user `environment_variables` still takes precedence to override) and `AWS_SES_CONFIGURATION_SET` (name of the per-app SES configuration set, so apps can attach it to outgoing messages and pick up reputation metrics / event publishing without re-deriving the name).
- New output `ses_configuration_set_name` exposing the configuration set name for callers that need it outside the container env.

## [2.5.0] - 2026-05-06

### Added
- `enable_bedrock` variable (default `false`). When `true`, attaches an IAM policy to the ECS task role granting `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` on `anthropic.*` foundation models and the matching cross-region inference profiles in the current account. Use this when the application calls Bedrock with the task role rather than an Anthropic API key — removes the need to ship `RAILS_MASTER_KEY` or store an Anthropic key in SSM.

## [2.4.1] - 2026-05-06

### Changed
- Set `timeouts.update = "60m"` on app and worker `aws_ecs_service` resources. Pairs with the `wait_for_steady_state` setting added in 2.4.0: the default 20-minute wait is too tight for services with longer ALB deregistration delays or slower container startup, causing terraform to mark applies failed when the rolling deploy would have succeeded a minute or two later. 60m is a sensible upper bound — past that the deployment circuit breaker has almost certainly already rolled back.

## [2.4.0] - 2026-05-05

### Changed
- App and worker `aws_ecs_service` resources now set `wait_for_steady_state = true`. Terraform apply blocks until the rolling deployment reaches steady state (or the deployment circuit breaker rolls back), so the apply's exit status reflects the actual deploy outcome rather than just the API call to update the service. Without this, opsitron Requests were being marked completed before new task definitions were live, leaving stale env/secret values in serving tasks.

## [2.3.0] - 2026-04-15

### Added
- `alb_zone_id` output — Route53 hosted zone ID of the ALB, needed by opsitron's domain alias provisioner to create alias DNS records. Without this, `entrypoint_zone_id` on the Environment was never populated after infra apply.

### Fixed
- HCL formatting alignment in locals and environment variable blocks

## [2.2.0] - 2026-03-31

### Fixed
- Use `ssm_prefix` for database password SSM parameter path
- Add `RAILS_ENV`, `SECRET_KEY_BASE`, `APP_HOST` environment variables to task definition
- Fix ECS health check configuration
- Fix secret name reference

## [2.1.0] - 2026-03-31

### Added
- `application` variable for SSM path convention (`/{application}/{environment}/...`)
- ECS cluster name and service name written to SSM for deploy workflow discovery

## [2.0.0] - 2026-02-25

### Changed
- **Breaking**: Removed `subdomain` variable — use external certificate ARN instead
- Accept external ACM certificate ARN directly

## [1.0.0] - 2026-02-19

### Added
- Initial ECS Fargate module with ALB, auto-scaling, optional Aurora PostgreSQL, Redis, S3, worker service, and SES
