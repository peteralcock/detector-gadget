# ------------------------------------------------------
# ECR Repositories
# ------------------------------------------------------

resource "aws_ecr_repository" "web_app" {
  name                 = "detector-gadget-web-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "detector-gadget-web-app"
    Environment = var.environment
  }
}

resource "aws_ecr_repository" "worker" {
  name                 = "detector-gadget-worker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "detector-gadget-worker"
    Environment = var.environment
  }
}

resource "aws_ecr_repository" "bulk_extractor" {
  name                 = "detector-gadget-bulk-extractor"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "detector-gadget-bulk-extractor"
    Environment = var.environment
  }
}

# ------------------------------------------------------
# ECS Cluster
# ------------------------------------------------------

resource "aws_ecs_cluster" "detector_gadget_cluster" {
  name = "detector-gadget-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "detector-gadget-cluster"
    Environment = var.environment
  }
}

# ------------------------------------------------------
# IAM Roles for ECS
# ------------------------------------------------------

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "detector-gadget-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "detector-gadget-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ecs_task_policy" {
  name        = "detector-gadget-ecs-task-policy"
  description = "Policy for ECS tasks"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpDelete",
          "secretsmanager:GetSecretValue",
          "sns:Publish"
        ]
        Resource = [
          aws_s3_bucket.evidence_bucket.arn,
          "${aws_s3_bucket.evidence_bucket.arn}/*",
          aws_s3_bucket.reports_bucket.arn,
          "${aws_s3_bucket.reports_bucket.arn}/*",
          aws_s3_bucket.artifacts_bucket.arn,
          "${aws_s3_bucket.artifacts_bucket.arn}/*",
          "${aws_elasticsearch_domain.entity_graph.arn}/*",
          aws_sns_topic.new_evidence_notification.arn,
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:detector-gadget-*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}

# ------------------------------------------------------
# ECS Task Definitions
# ------------------------------------------------------

resource "aws_ecs_task_definition" "web_app" {
  family                   = "detector-gadget-web-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.web_app_cpu
  memory                   = var.web_app_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "detector-gadget-web-app"
      image     = "${aws_ecr_repository.web_app.repository_url}:latest"
      essential = true
      
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
      
      environment = [
        {
          name  = "FLASK_APP"
          value = "app.py"
        },
        {
          name  = "FLASK_DEBUG"
          value = var.environment == "development" ? "True" : "False"
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "EVIDENCE_BUCKET"
          value = aws_s3_bucket.evidence_bucket.id
        },
        {
          name  = "REPORTS_BUCKET"
          value = aws_s3_bucket.reports_bucket.id
        },
        {
          name  = "ARTIFACTS_BUCKET"
          value = aws_s3_bucket.artifacts_bucket.id
        },
        {
          name  = "ELASTICSEARCH_ENDPOINT"
          value = "https://${aws_elasticsearch_domain.entity_graph.endpoint}"
        },
        {
          name  = "DATABASE_URL"
          value = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.endpoint}/${var.db_name}"
        },
        {
          name  = "CELERY_BROKER_URL"
          value = "redis://${aws_elasticache_replication_group.redis.configuration_endpoint_address}:6379/0"
        },
        {
          name  = "CELERY_RESULT_BACKEND"
          value = "redis://${aws_elasticache_replication_group.redis.configuration_endpoint_address}:6379/0"
        }
      ],

      secrets = [
        {
          name      = "ELASTICSEARCH_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.elasticsearch_credentials.arn}:username::"
        },
        {
          name      = "ELASTICSEARCH_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.elasticsearch_credentials.arn}:password::"
        },
        {
          name      = "SECRET_KEY"
          valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:secret_key::"
        }
      ],
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web_app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "web-app"
        }
      }
    }
  ])

  tags = {
    Name        = "detector-gadget-web-app"
    Environment = var.environment
  }
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "detector-gadget-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "detector-gadget-worker"
      image     = "${aws_ecr_repository.worker.repository_url}:latest"
      essential = true
      
      command = ["worker"]
      
      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "EVIDENCE_BUCKET"
          value = aws_s3_bucket.evidence_bucket.id
        },
        {
          name  = "REPORTS_BUCKET"
          value = aws_s3_bucket.reports_bucket.id
        },
        {
          name  = "ARTIFACTS_BUCKET"
          value = aws_s3_bucket.artifacts_bucket.id
        },
        {
          name  = "ELASTICSEARCH_ENDPOINT"
          value = "https://${aws_elasticsearch_domain.entity_graph.endpoint}"
        },
        {
          name  = "DATABASE_URL"
          value = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.endpoint}/${var.db_name}"
        },
        {
          name  = "CELERY_BROKER_URL"
          value = "redis://${aws_elasticache_replication_group.redis.configuration_endpoint_address}:6379/0"
        },
        {
          name  = "CELERY_RESULT_BACKEND"
          value = "redis://${aws_elasticache_replication_group.redis.configuration_endpoint_address}:6379/0"
        }
      ],

      secrets = [
        {
          name      = "ELASTICSEARCH_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.elasticsearch_credentials.arn}:username::"
        },
        {
          name      = "ELASTICSEARCH_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.elasticsearch_credentials.arn}:password::"
        }
      ],
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.worker.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "worker"
        }
      }
    }
  ])

  tags = {
    Name        = "detector-gadget-worker"
    Environment = var.environment
  }
}

# ------------------------------------------------------
# ECS Services
# ------------------------------------------------------

resource "aws_ecs_service" "web_app" {
  name                               = "detector-gadget-web-app"
  cluster                            = aws_ecs_cluster.detector_gadget_cluster.id
  task_definition                    = aws_ecs_task_definition.web_app.arn
  desired_count                      = var.web_app_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web_app.arn
    container_name   = "detector-gadget-web-app"
    container_port   = 5000
  }

  depends_on = [
    aws_lb_listener.https,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]

  tags = {
    Name        = "detector-gadget-web-app-service"
    Environment = var.environment
  }
}

resource "aws_ecs_service" "worker" {
  name                               = "detector-gadget-worker"
  cluster                            = aws_ecs_cluster.detector_gadget_cluster.id
  task_definition                    = aws_ecs_task_definition.worker.arn
  desired_count                      = var.worker_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]

  tags = {
    Name        = "detector-gadget-worker-service"
    Environment = var.environment
  }
}

# ------------------------------------------------------
# CloudWatch Log Groups
# ------------------------------------------------------

resource "aws_cloudwatch_log_group" "web_app" {
  name              = "/ecs/detector-gadget-web-app"
  retention_in_days = 30

  tags = {
    Name        = "detector-gadget-web-app-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/detector-gadget-worker"
  retention_in_days = 30

  tags = {
    Name        = "detector-gadget-worker-logs"
    Environment = var.environment
  }
}

# ------------------------------------------------------
# Application Load Balancer
# ------------------------------------------------------

resource "aws_lb" "detector_gadget" {
  name               = "detector-gadget-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  enable_deletion_protection = var.environment == "production" ? true : false

  tags = {
    Name        = "detector-gadget-alb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "web_app" {
  name        = "detector-gadget-web-app-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.detector_gadget_vpc.id
  target_type = "ip"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = {
    Name        = "detector-gadget-web-app-tg"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.detector_gadget.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.detector_gadget.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_app.arn
  }
}

# ------------------------------------------------------
# Auto Scaling
# ------------------------------------------------------

resource "aws_appautoscaling_target" "web_app" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.detector_gadget_cluster.name}/${aws_ecs_service.web_app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "web_app_cpu" {
  name               = "detector-gadget-web-app-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.web_app.resource_id
  scalable_dimension = aws_appautoscaling_target.web_app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.web_app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_target" "worker" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.detector_gadget_cluster.name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "worker_cpu" {
  name               = "detector-gadget-worker-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "worker_queue_depth" {
  name               = "detector-gadget-worker-queue-depth-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker.service_namespace

  target_tracking_scaling_policy_configuration {
    customized_metric_specification {
      metric_dimension {
        name  = "QueueName"
        value = aws_sqs_queue.processing_queue.name
      }
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      statistic   = "Average"
    }
    target_value       = 10.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
