# =============================================================================
# ElastiCache Redis (conditional on enable_redis)
# =============================================================================

resource "aws_elasticache_subnet_group" "redis" {
  count = var.enable_redis ? 1 : 0

  name       = "${local.name_prefix}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis-subnet-group"
  })
}

resource "aws_elasticache_parameter_group" "redis" {
  count = var.enable_redis ? 1 : 0

  name   = "${local.name_prefix}-redis-params"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis-params"
  })
}

resource "aws_elasticache_cluster" "redis" {
  count = var.enable_redis ? 1 : 0

  cluster_id           = "${local.name_prefix}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = var.redis_num_cache_nodes
  parameter_group_name = aws_elasticache_parameter_group.redis[0].name
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis[0].name
  security_group_ids   = [aws_security_group.redis[0].id]

  snapshot_retention_limit = local.is_prod ? 7 : 1
  snapshot_window          = "03:00-05:00"
  maintenance_window       = "sun:05:00-sun:06:00"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis"
  })
}
