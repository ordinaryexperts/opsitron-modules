# =============================================================================
# Aurora Serverless v2 PostgreSQL (conditional on enable_rds)
# =============================================================================

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  count = var.enable_rds ? 1 : 0

  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

# Database Password
resource "random_password" "db_password" {
  count = var.enable_rds ? 1 : 0

  length  = 32
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  count = var.enable_rds ? 1 : 0

  name  = "/${local.name_prefix}/database/password"
  type  = "SecureString"
  value = random_password.db_password[0].result

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-password"
  })
}

# KMS Key for RDS Encryption
resource "aws_kms_key" "rds" {
  count = var.enable_rds ? 1 : 0

  description             = "KMS key for RDS encryption - ${local.name_prefix}"
  deletion_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-kms"
  })
}

resource "aws_kms_alias" "rds" {
  count = var.enable_rds ? 1 : 0

  name          = "alias/${local.name_prefix}-rds"
  target_key_id = aws_kms_key.rds[0].key_id
}

# Cluster Parameter Group
resource "aws_rds_cluster_parameter_group" "main" {
  count = var.enable_rds ? 1 : 0

  name        = "${local.name_prefix}-cluster-pg"
  family      = "aurora-postgresql${local.postgres_major_version}"
  description = "Cluster parameter group for ${local.name_prefix}"

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pgaudit"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster-pg"
  })
}

# Instance Parameter Group
resource "aws_db_parameter_group" "main" {
  count = var.enable_rds ? 1 : 0

  name        = "${local.name_prefix}-db-pg"
  family      = "aurora-postgresql${local.postgres_major_version}"
  description = "DB parameter group for ${local.name_prefix}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-pg"
  })
}

# Aurora Serverless v2 Cluster
resource "aws_rds_cluster" "main" {
  count = var.enable_rds ? 1 : 0

  cluster_identifier              = "${local.name_prefix}-cluster"
  engine                          = "aurora-postgresql"
  engine_version                  = var.postgres_version
  engine_mode                     = "provisioned"
  database_name                   = var.database_name
  master_username                 = var.database_username
  master_password                 = random_password.db_password[0].result
  db_subnet_group_name            = aws_db_subnet_group.main[0].name
  vpc_security_group_ids          = [aws_security_group.database[0].id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main[0].name

  storage_encrypted         = true
  kms_key_id                = aws_kms_key.rds[0].arn
  deletion_protection       = var.enable_deletion_protection || local.is_prod
  skip_final_snapshot       = !local.is_prod
  final_snapshot_identifier = local.is_prod ? "${local.name_prefix}-final-snapshot" : null

  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_serverless_min_capacity
    max_capacity = var.aurora_serverless_max_capacity
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-cluster"
    Engine = "Aurora Serverless v2"
  })

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier
    ]
  }
}

# Aurora Serverless v2 Instances
resource "aws_rds_cluster_instance" "main" {
  count = var.enable_rds ? var.instance_count : 0

  identifier              = "${local.name_prefix}-db-${count.index}"
  cluster_identifier      = aws_rds_cluster.main[0].id
  instance_class          = "db.serverless"
  engine                  = aws_rds_cluster.main[0].engine
  engine_version          = aws_rds_cluster.main[0].engine_version
  db_parameter_group_name = aws_db_parameter_group.main[0].name

  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn          = aws_iam_role.rds_enhanced_monitoring[0].arn

  promotion_tier = count.index

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-db-${count.index}"
    Engine = "Aurora Serverless v2"
  })
}

# Enhanced Monitoring IAM Role
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.enable_rds ? 1 : 0

  name = "${local.name_prefix}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.enable_rds ? 1 : 0

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
