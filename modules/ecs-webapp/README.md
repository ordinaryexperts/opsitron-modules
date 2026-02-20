# ECS Webapp Module

Deploys a containerized web application to AWS ECS Fargate with optional Aurora Serverless v2 database, ElastiCache Redis, S3 storage, background worker service, and SES email sending.

Designed for use with client accounts that already have VPCs provisioned (e.g., via Landing Zone Accelerator). The module takes VPC/subnet IDs as inputs rather than creating networking resources.

## Features

- ECS Fargate cluster with app service and ALB
- ACM certificate with DNS validation
- Auto-scaling (CPU and memory target tracking)
- CloudWatch log groups and alarms
- SNS alerts topic
- Generic environment variable and secrets injection
- Deployment circuit breaker with rollback
- ECS Exec support for interactive debugging

### Optional Components (Feature Flags)

| Flag | Default | Description |
|------|---------|-------------|
| `enable_rds` | `true` | Aurora Serverless v2 PostgreSQL with KMS encryption |
| `enable_redis` | `false` | ElastiCache Redis cluster |
| `enable_s3` | `false` | S3 bucket with encryption and CORS |
| `enable_worker` | `false` | Background worker service (same image, different command) |
| `enable_ses` | `false` | SES domain identity with DKIM and SPF |

## Usage

### Minimal Example

```hcl
module "webapp" {
  source = "github.com/ordinaryexperts/platform-modules//modules/ecs-webapp?ref=ecs-webapp-v1.0.0"

  name               = "my-app"
  environment        = "dev1"
  vpc_id             = "vpc-abc123"
  public_subnet_ids  = ["subnet-pub1", "subnet-pub2"]
  private_subnet_ids = ["subnet-priv1", "subnet-priv2"]
  ecr_repository_url = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-app"
  domain_name        = "example.com"
  subdomain          = "app"
  route53_zone_id    = "Z1234567890"

  # RDS enabled by default - provide database subnets
  database_subnet_ids = ["subnet-db1", "subnet-db2"]
}
```

### Full Example

```hcl
module "webapp" {
  source = "github.com/ordinaryexperts/platform-modules//modules/ecs-webapp?ref=ecs-webapp-v1.0.0"

  name               = "my-app"
  environment        = "prod1"
  vpc_id             = "vpc-abc123"
  public_subnet_ids  = ["subnet-pub1", "subnet-pub2"]
  private_subnet_ids = ["subnet-priv1", "subnet-priv2"]
  ecr_repository_url = "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-app"
  domain_name        = "example.com"
  subdomain          = "app"
  route53_zone_id    = "Z1234567890"

  # ECS
  task_cpu      = 1024
  task_memory   = 2048
  desired_count = 2

  # Auto-scaling
  min_capacity     = 2
  max_capacity     = 20
  cpu_target_value = 60

  # RDS
  enable_rds                     = true
  database_subnet_ids            = ["subnet-db1", "subnet-db2"]
  database_name                  = "myapp"
  aurora_serverless_min_capacity = 1
  aurora_serverless_max_capacity = 8
  instance_count                 = 2

  # Redis
  enable_redis      = true
  redis_node_type   = "cache.t4g.small"

  # S3
  enable_s3 = true

  # Worker
  enable_worker        = true
  worker_command       = ["bin/rails", "solid_queue:start"]
  worker_task_cpu      = 512
  worker_task_memory   = 1024
  worker_desired_count = 2

  # SES
  enable_ses = true

  # Custom env vars (merged with computed infra vars)
  environment_variables = {
    RAILS_ENV                = "production"
    RAILS_LOG_TO_STDOUT      = "true"
    RAILS_SERVE_STATIC_FILES = "true"
  }

  # Custom secrets (merged with computed infra secrets)
  secrets = {
    GOOGLE_CLIENT_ID     = "arn:aws:secretsmanager:us-west-2:123456789012:secret:app-secrets:google_client_id::"
    GOOGLE_CLIENT_SECRET = "arn:aws:secretsmanager:us-west-2:123456789012:secret:app-secrets:google_client_secret::"
  }

  tags = {
    Project = "my-app"
    Owner   = "platform"
  }
}
```

## Environment Variables

The module automatically injects infrastructure-related environment variables into the container. User-provided `environment_variables` are merged with (and take precedence over) these computed values:

| Variable | Condition | Source |
|----------|-----------|--------|
| `AWS_DEFAULT_REGION` | Always | Current AWS region |
| `AWS_ACCOUNT_ID` | Always | Current AWS account ID |
| `DATABASE_HOST` | `enable_rds` | Aurora cluster endpoint |
| `DATABASE_PORT` | `enable_rds` | Aurora cluster port |
| `DATABASE_NAME` | `enable_rds` | Aurora database name |
| `DATABASE_USERNAME` | `enable_rds` | Aurora master username |
| `REDIS_URL` | `enable_redis` | Full Redis connection URL |
| `AWS_S3_BUCKET` | `enable_s3` | S3 bucket name |

## Secrets

Similarly, secrets are auto-injected and merged with user-provided `secrets`:

| Secret | Condition | Source |
|--------|-----------|--------|
| `APP_SECRET` | Always | Generated 128-char random string in SSM |
| `DATABASE_PASSWORD` | `enable_rds` | Generated random password in SSM |

## CI/CD Integration

The module creates an SSM parameter for the container image tag (`/{name}-{environment}/container-image-tag`). Your CI/CD pipeline should:

1. Build and push the image to ECR
2. Update the SSM parameter with the new tag
3. Update the ECS service to force a new deployment

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `name` | Application name for resource naming | `string` | | yes |
| `vpc_id` | VPC ID | `string` | | yes |
| `public_subnet_ids` | Public subnet IDs for ALB (min 2) | `list(string)` | | yes |
| `private_subnet_ids` | Private subnet IDs for ECS tasks | `list(string)` | | yes |
| `ecr_repository_url` | ECR repository URL (without tag) | `string` | | yes |
| `domain_name` | Base domain name | `string` | | yes |
| `route53_zone_id` | Route53 hosted zone ID | `string` | | yes |
| `environment` | Environment name | `string` | `"dev"` | no |
| `subdomain` | Subdomain prefix | `string` | `""` | no |
| `container_port` | Container port | `number` | `3000` | no |
| `health_check_path` | Health check path | `string` | `"/up"` | no |
| `task_cpu` | App task CPU units | `number` | `512` | no |
| `task_memory` | App task memory (MiB) | `number` | `1024` | no |
| `desired_count` | App task count | `number` | `1` | no |
| `initial_image_tag` | Initial image tag | `string` | `"latest"` | no |
| `container_command` | Override container command | `list(string)` | `null` | no |
| `enable_execute_command` | Enable ECS Exec | `bool` | `true` | no |
| `environment_variables` | Extra env vars | `map(string)` | `{}` | no |
| `secrets` | Extra secrets (name to ARN) | `map(string)` | `{}` | no |
| `min_capacity` | Min auto-scale tasks | `number` | `1` | no |
| `max_capacity` | Max auto-scale tasks | `number` | `10` | no |
| `cpu_target_value` | CPU scaling target % | `number` | `70` | no |
| `memory_target_value` | Memory scaling target % | `number` | `80` | no |
| `enable_rds` | Create Aurora database | `bool` | `true` | no |
| `enable_redis` | Create Redis cluster | `bool` | `false` | no |
| `enable_s3` | Create S3 bucket | `bool` | `false` | no |
| `enable_worker` | Create worker service | `bool` | `false` | no |
| `enable_ses` | Create SES identity | `bool` | `false` | no |
| `database_subnet_ids` | DB subnet IDs | `list(string)` | `[]` | when RDS enabled |
| `database_name` | Database name | `string` | `"app"` | no |
| `database_username` | DB master username | `string` | `"app"` | no |
| `postgres_version` | Aurora PostgreSQL version | `string` | `"17.4"` | no |
| `aurora_serverless_min_capacity` | Min ACU | `number` | `0.5` | no |
| `aurora_serverless_max_capacity` | Max ACU | `number` | `4` | no |
| `instance_count` | Aurora instance count | `number` | `1` | no |
| `redis_node_type` | Redis node type | `string` | `"cache.t4g.micro"` | no |
| `redis_num_cache_nodes` | Redis node count | `number` | `1` | no |
| `worker_command` | Worker command | `list(string)` | `null` | no |
| `worker_task_cpu` | Worker CPU units | `number` | `256` | no |
| `worker_task_memory` | Worker memory (MiB) | `number` | `512` | no |
| `worker_desired_count` | Worker task count | `number` | `1` | no |
| `log_retention_days` | Log retention days | `number` | `30` | no |
| `tags` | Resource tags | `map(string)` | `{}` | no |
| `ssl_policy` | ALB SSL policy | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| `enable_deletion_protection` | Deletion protection | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| `ecs_cluster_name` | ECS cluster name |
| `ecs_cluster_arn` | ECS cluster ARN |
| `ecs_service_name` | App service name |
| `alb_dns_name` | ALB DNS name |
| `alb_arn` | ALB ARN |
| `app_url` | Full HTTPS application URL |
| `container_image_tag_parameter_name` | SSM parameter for image tag |
| `task_execution_role_arn` | Execution role ARN |
| `task_role_arn` | Task role ARN |
| `alb_security_group_id` | ALB security group ID |
| `ecs_security_group_id` | ECS security group ID |
| `sns_alerts_topic_arn` | SNS alerts topic ARN |
| `database_endpoint` | Aurora endpoint (if RDS enabled) |
| `database_name` | Database name (if RDS enabled) |
| `database_password_parameter_arn` | DB password SSM ARN (if RDS enabled) |
| `redis_endpoint` | Redis endpoint (if Redis enabled) |
| `redis_url` | Redis URL (if Redis enabled) |
| `s3_bucket_name` | S3 bucket name (if S3 enabled) |
| `s3_bucket_arn` | S3 bucket ARN (if S3 enabled) |
| `worker_service_name` | Worker service name (if worker enabled) |
| `ses_domain_identity_arn` | SES identity ARN (if SES enabled) |
