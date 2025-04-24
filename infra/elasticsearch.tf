# ------------------------------------------------------
# Elasticsearch Domain for Entity Analytics
# ------------------------------------------------------

resource "aws_elasticsearch_domain" "entity_graph" {
  domain_name           = var.elasticsearch_domain_name
  elasticsearch_version = "7.10"

  cluster_config {
    instance_type            = var.elasticsearch_instance_type
    instance_count           = var.elasticsearch_instance_count
    zone_awareness_enabled   = var.elasticsearch_instance_count > 1 ? true : false
    
    # Enable zone awareness only if we have multiple instances
    dynamic "zone_awareness_config" {
      for_each = var.elasticsearch_instance_count > 1 ? [1] : []
      content {
        availability_zone_count = 2
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.elasticsearch_volume_size
    volume_type = "gp2"
  }

  vpc_options {
    subnet_ids         = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    security_group_ids = [aws_security_group.es_sg.id]
  }

  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
  }

  # Encrypt at rest
  encrypt_at_rest {
    enabled = true
  }

  # Node-to-node encryption
  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    
    master_user_options {
      master_user_name     = var.elasticsearch_master_user
      master_user_password = var.elasticsearch_master_password
    }
  }

  tags = {
    Name        = "detector-gadget-elasticsearch"
    Environment = var.environment
  }

  depends_on = [
    aws_iam_service_linked_role.es
  ]
}

# Create a service-linked role for Elasticsearch if it doesn't exist
resource "aws_iam_service_linked_role" "es" {
  aws_service_name = "es.amazonaws.com"
  description      = "Service-linked role for Elasticsearch"
  
  # Ignore errors if the role already exists
  provisioner "local-exec" {
    command = "aws iam get-role --role-name AWSServiceRoleForAmazonElasticsearchService || aws iam create-service-linked-role --aws-service-name es.amazonaws.com"
    on_failure = continue
  }
}

# Access policy for the Elasticsearch domain
resource "aws_elasticsearch_domain_policy" "entity_graph_policy" {
  domain_name = aws_elasticsearch_domain.entity_graph.domain_name

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ecs_task_execution_role.arn
        }
        Action = [
          "es:ESHttp*"
        ]
        Resource = "${aws_elasticsearch_domain.entity_graph.arn}/*"
      }
    ]
  })
}

# ------------------------------------------------------
# Lambda Functions for Elasticsearch Integration
# ------------------------------------------------------

resource "aws_iam_role" "es_indexer_role" {
  name = "detector-gadget-es-indexer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "es_indexer_policy" {
  name        = "detector-gadget-es-indexer-policy"
  description = "Policy for Lambda to index data into Elasticsearch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpGet",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:logs:*:*:*",
          "${aws_elasticsearch_domain.entity_graph.arn}/*",
          aws_sqs_queue.processing_queue.arn,
          "${aws_s3_bucket.evidence_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "es_indexer_policy_attachment" {
  role       = aws_iam_role.es_indexer_role.name
  policy_arn = aws_iam_policy.es_indexer_policy.arn
}

# Lambda function to process entities and index them to Elasticsearch
resource "aws_lambda_function" "entity_processor" {
  function_name    = "detector-gadget-entity-processor"
  role             = aws_iam_role.es_indexer_role.arn
  handler          = "entity_processor.handler"
  runtime          = "python3.9"
  filename         = data.archive_file.entity_processor_zip.output_path
  source_code_hash = data.archive_file.entity_processor_zip.output_base64sha256
  timeout          = 300
  memory_size      = 1024

  environment {
    variables = {
      ELASTICSEARCH_ENDPOINT = "https://${aws_elasticsearch_domain.entity_graph.endpoint}",
      ELASTICSEARCH_USERNAME = var.elasticsearch_master_user,
      ELASTICSEARCH_PASSWORD = var.elasticsearch_master_password,
      EVIDENCE_BUCKET        = aws_s3_bucket.evidence_bucket.id,
      ARTIFACTS_BUCKET       = aws_s3_bucket.artifacts_bucket.id,
      REPORTS_BUCKET         = aws_s3_bucket.reports_bucket.id
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    security_group_ids = [aws_security_group.ecs_sg.id]
  }

  tags = {
    Name        = "detector-gadget-entity-processor"
    Environment = var.environment
  }
}

# Lambda function to generate POI relationship graphs
resource "aws_lambda_function" "poi_graph_generator" {
  function_name    = "detector-gadget-poi-graph-generator"
  role             = aws_iam_role.es_indexer_role.arn
  handler          = "poi_graph_generator.handler"
  runtime          = "python3.9"
  filename         = data.archive_file.poi_graph_generator_zip.output_path
  source_code_hash = data.archive_file.poi_graph_generator_zip.output_base64sha256
  timeout          = 300
  memory_size      = 1024

  environment {
    variables = {
      ELASTICSEARCH_ENDPOINT = "https://${aws_elasticsearch_domain.entity_graph.endpoint}",
      ELASTICSEARCH_USERNAME = var.elasticsearch_master_user,
      ELASTICSEARCH_PASSWORD = var.elasticsearch_master_password,
      REPORTS_BUCKET         = aws_s3_bucket.reports_bucket.id
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    security_group_ids = [aws_security_group.ecs_sg.id]
  }

  tags = {
    Name        = "detector-gadget-poi-graph-generator"
    Environment = var.environment
  }
}

# Trigger for entity processor lambda from SQS
resource "aws_lambda_event_source_mapping" "entity_processor_trigger" {
  event_source_arn = aws_sqs_queue.processing_queue.arn
  function_name    = aws_lambda_function.entity_processor.function_name
  batch_size       = 10
  enabled          = true
}

# Zip files for Lambda functions
data "archive_file" "entity_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/entity_processor.zip"
  source {
    content  = file("${path.module}/lambda/entity_processor.py")
    filename = "entity_processor.py"
  }
}

data "archive_file" "poi_graph_generator_zip" {
  type        = "zip"
  output_path = "${path.module}/poi_graph_generator.zip"
  source {
    content  = file("${path.module}/lambda/poi_graph_generator.py")
    filename = "poi_graph_generator.py"
  }
}

# ------------------------------------------------------
# CloudWatch Scheduled Event for POI Graph Generation
# ------------------------------------------------------

resource "aws_cloudwatch_event_rule" "poi_graph_generator_schedule" {
  name                = "detector-gadget-poi-graph-generator-schedule"
  description         = "Trigger POI graph generation daily"
  schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "poi_graph_generator_target" {
  rule      = aws_cloudwatch_event_rule.poi_graph_generator_schedule.name
  target_id = "detector-gadget-poi-graph-generator"
  arn       = aws_lambda_function.poi_graph_generator.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_poi_graph_generator" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.poi_graph_generator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.poi_graph_generator_schedule.arn
}
