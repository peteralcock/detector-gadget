# ------------------------------------------------------
# Output values
# ------------------------------------------------------

output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.detector_gadget.dns_name
}

output "evidence_bucket" {
  description = "Name of the evidence S3 bucket"
  value       = aws_s3_bucket.evidence_bucket.id
}

output "reports_bucket" {
  description = "Name of the reports S3 bucket"
  value       = aws_s3_bucket.reports_bucket.id
}

output "artifacts_bucket" {
  description = "Name of the artifacts S3 bucket"
  value       = aws_s3_bucket.artifacts_bucket.id
}

output "elasticsearch_endpoint" {
  description = "Endpoint of the Elasticsearch domain"
  value       = aws_elasticsearch_domain.entity_graph.endpoint
}

output "elasticsearch_dashboard" {
  description = "Kibana dashboard URL"
  value       = "https://${aws_elasticsearch_domain.entity_graph.endpoint}/_plugin/kibana/"
}

output "rds_endpoint" {
  description = "Endpoint of the RDS instance"
  value       = aws_db_instance.postgres.endpoint
}

output "redis_endpoint" {
  description = "Endpoint of the Redis cluster"
  value       = aws_elasticache_replication_group.redis.configuration_endpoint_address
}

output "ecr_repositories" {
  description = "ECR repository URLs"
  value = {
    web_app        = aws_ecr_repository.web_app.repository_url
    worker         = aws_ecr_repository.worker.repository_url
    bulk_extractor = aws_ecr_repository.bulk_extractor.repository_url
  }
}

output "ecs_cluster" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.detector_gadget_cluster.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.detector_gadget_vpc.id
}

output "entity_processor_lambda" {
  description = "Entity processor Lambda function name"
  value       = aws_lambda_function.entity_processor.function_name
}

output "poi_graph_generator_lambda" {
  description = "POI graph generator Lambda function name"
  value       = aws_lambda_function.poi_graph_generator.function_name
}

output "processing_queue_url" {
  description = "URL of the SQS processing queue"
  value       = aws_sqs_queue.processing_queue.url
}

output "data_get_started" {
  description = "Instructions to get started"
  value       = <<EOT
To get started with Detector Gadget:

1. Push Docker images to ECR:
   - Web App: ${aws_ecr_repository.web_app.repository_url}
   - Worker: ${aws_ecr_repository.worker.repository_url}
   - Bulk Extractor: ${aws_ecr_repository.bulk_extractor.repository_url}

2. Access the application at: http://${aws_lb.detector_gadget.dns_name}

3. Upload evidence files to: s3://${aws_s3_bucket.evidence_bucket.id}

4. View POI graph reports at: s3://${aws_s3_bucket.reports_bucket.id}/graphs/

5. Explore entity relationships in Elasticsearch: ${aws_elasticsearch_domain.entity_graph.endpoint}
EOT
}
