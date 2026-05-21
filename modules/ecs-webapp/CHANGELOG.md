# Changelog

All notable changes to this module are documented in this file.

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
