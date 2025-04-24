# ------------------------------------------------------
# RDS PostgreSQL Database
# ------------------------------------------------------

resource "aws_db_subnet_group" "postgres" {
  name       = "detector-gadget-postgres-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name        = "detector-gadget-postgres-subnet-group"
    Environment = var.environment
  }
}

resource "aws_db_parameter_group" "postgres" {
  name   = "detector-gadget-postgres-params"
  family = "postgres13"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name        = "detector-gadget-postgres-params"
    Environment = var.environment
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "detector-gadget-postgres"
  engine                 = "postgres"
  engine_version         = "13.7"
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  storage_type           = "gp2"
  storage_encrypted      = true
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  port                   = 5432
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false
  skip_final_snapshot    = var.environment == "production" ? false : true
  deletion_protection    = var.environment == "production" ? true : false
  backup_retention_period = var.environment == "production" ? 7 : 1
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"
  multi_az               = var.environment == "production" ? true : false
  copy_tags_to_snapshot  = true
  
  tags = {
    Name        = "detector-gadget-postgres"
    Environment = var.environment
  }
}

# ------------------------------------------------------
# ElastiCache Redis
# ------------------------------------------------------

resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "detector-gadget-redis-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  
  tags = {
    Name        = "detector-gadget-redis-subnet-group"
    Environment = var.environment
  }
}

resource "aws_elasticache_parameter_group" "redis_params" {
  name   = "detector-gadget-redis-params"
  family = "redis6.x"

  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  tags = {
    Name        = "detector-gadget-redis-params"
    Environment = var.environment
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "detector-gadget-redis"
  description                   = "Detector Gadget Redis cluster for Celery"
  node_type                     = var.redis_node_type
  port                          = 6379
  parameter_group_name          = aws_elasticache_parameter_group.redis_params.name
  subnet_group_name             = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids            = [aws_security_group.redis_sg.id]
  automatic_failover_enabled    = var.environment == "production" ? true : false
  multi_az_enabled              = var.environment == "production" ? true : false
  num_cache_clusters            = var.environment == "production" ? 2 : 1
  at_rest_encryption_enabled    = true
  transit_encryption_enabled    = true
  snapshot_retention_limit      = var.environment == "production" ? 7 : 1
  snapshot_window               = "03:00-04:00"
  maintenance_window            = "sun:05:00-sun:06:00"
  
  tags = {
    Name        = "detector-gadget-redis"
    Environment = var.environment
  }
}

# ------------------------------------------------------
# Secrets Manager for Database Credentials
# ------------------------------------------------------

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "detector-gadget-db-credentials"
  description = "Database credentials for Detector Gadget"
  
  tags = {
    Name        = "detector-gadget-db-credentials"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
    dbname   = var.db_name
  })
}

resource "aws_secretsmanager_secret" "elasticsearch_credentials" {
  name        = "detector-gadget-elasticsearch-credentials"
  description = "Elasticsearch credentials for Detector Gadget"
  
  tags = {
    Name        = "detector-gadget-elasticsearch-credentials"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "elasticsearch_credentials" {
  secret_id     = aws_secretsmanager_secret.elasticsearch_credentials.id
  secret_string = jsonencode({
    username = var.elasticsearch_master_user
    password = var.elasticsearch_master_password
  })
}

resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "detector-gadget-app-secrets"
  description = "Application secrets for Detector Gadget"
  
  tags = {
    Name        = "detector-gadget-app-secrets"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id     = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    secret_key = var.flask_secret_key
  })
}
