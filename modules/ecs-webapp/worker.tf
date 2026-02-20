# =============================================================================
# Worker Service (conditional on enable_worker)
# =============================================================================

# Worker Log Group
resource "aws_cloudwatch_log_group" "worker" {
  count = var.enable_worker ? 1 : 0

  name              = "/ecs/worker/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-worker-logs"
  })
}

# Worker Task Definition
resource "aws_ecs_task_definition" "worker" {
  count = var.enable_worker ? 1 : 0

  family                   = "${local.name_prefix}-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.worker_task_cpu
  memory                   = var.worker_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    merge(
      {
        name  = "worker"
        image = "${var.ecr_repository_url}:${data.aws_ssm_parameter.container_image_tag.value}"

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
            "awslogs-group"         = aws_cloudwatch_log_group.worker[0].name
            "awslogs-region"        = data.aws_region.current.id
            "awslogs-stream-prefix" = "ecs"
          }
        }
      },
      var.worker_command != null ? { command = var.worker_command } : {}
    )
  ])

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-worker-task"
  })
}

# Worker Service
resource "aws_ecs_service" "worker" {
  count = var.enable_worker ? 1 : 0

  name                   = "${local.name_prefix}-worker"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.worker[0].arn
  desired_count          = var.worker_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = var.enable_execute_command

  network_configuration {
    security_groups  = [aws_security_group.ecs.id]
    subnets          = var.private_subnet_ids
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  depends_on = [
    aws_iam_role_policy_attachment.ecs_execution_managed
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-worker-service"
  })
}
