# Changelog

All notable changes to this module are documented in this file.

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
