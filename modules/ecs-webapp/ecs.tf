# =============================================================================
# ECS Cluster
# =============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = false
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_cluster.name
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster"
  })
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# =============================================================================
# Container Image Tag (managed by CI/CD)
# =============================================================================

resource "aws_ssm_parameter" "container_image_tag" {
  name        = "${local.ssm_prefix}/container-image-tag"
  type        = "String"
  value       = var.initial_image_tag
  description = "Current container image tag for ${local.name_prefix}"

  tags = local.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}

data "aws_ssm_parameter" "container_image_tag" {
  name       = aws_ssm_parameter.container_image_tag.name
  depends_on = [aws_ssm_parameter.container_image_tag]
}

# =============================================================================
# App Task Definition
# =============================================================================

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    merge(
      {
        name  = "app"
        image = "${var.ecr_repository_url}:${data.aws_ssm_parameter.container_image_tag.value}"

        portMappings = [
          {
            containerPort = var.container_port
            protocol      = "tcp"
          }
        ]

        environment = [
          for k, v in local.computed_environment : {
            name  = k
            value = v
          }
        ]

        secrets = [
          for k, v in local.computed_secrets : {
            name      = k
            valueFrom = v
          }
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.app.name
            "awslogs-region"        = data.aws_region.current.id
            "awslogs-stream-prefix" = "ecs"
          }
        }

        healthCheck = {
          command = [
            "CMD-SHELL",
            "wget -qO- http://localhost:${var.container_port}${var.health_check_path} || curl -sf http://localhost:${var.container_port}${var.health_check_path} || exit 1"
          ]
          interval    = 30
          timeout     = 5
          retries     = 3
          startPeriod = 120
        }
      },
      var.container_command != null ? { command = var.container_command } : {}
    )
  ])

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-task"
  })
}

# =============================================================================
# App Service
# =============================================================================

resource "aws_ecs_service" "app" {
  name                   = "${local.name_prefix}-app"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.app.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = var.enable_execute_command

  network_configuration {
    security_groups  = [aws_security_group.ecs.id]
    subnets          = var.private_subnet_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  depends_on = [
    aws_lb_listener.https,
    aws_iam_role_policy_attachment.ecs_execution_managed
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-service"
  })
}

# =============================================================================
# SSM Parameters for Platform Deploy Workflow
# =============================================================================

resource "aws_ssm_parameter" "ecs_cluster_name" {
  name        = "${local.ssm_prefix}/ecs-cluster-name"
  type        = "String"
  value       = aws_ecs_cluster.main.name
  description = "ECS cluster name for ${local.name_prefix}"

  tags = local.common_tags
}

resource "aws_ssm_parameter" "ecs_service_name" {
  name        = "${local.ssm_prefix}/ecs-service-name"
  type        = "String"
  value       = aws_ecs_service.app.name
  description = "ECS service name for ${local.name_prefix}"

  tags = local.common_tags
}
