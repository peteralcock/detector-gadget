# ------------------------------------------------------
# General Configuration
# ------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"
}

# ------------------------------------------------------
# S3 Bucket Names
# ------------------------------------------------------

variable "evidence_bucket_name" {
  description = "Name of the S3 bucket for evidence files"
  type        = string
  default     = "detector-gadget-evidence"
}

variable "reports_bucket_name" {
  description = "Name of the S3 bucket for reports"
  type        = string
  default     = "detector-gadget-reports"
}

variable "artifacts_bucket_name" {
  description = "Name of the S3 bucket for artifacts"
  type        = string
  default     = "detector-gadget-artifacts"
}

variable "evidence_retention_days" {
  description = "Number of days to retain evidence files"
  type        = number
  default     = 3650  # 10 years by default
}

# ------------------------------------------------------
# Elasticsearch Configuration
# ------------------------------------------------------

variable "elasticsearch_domain_name" {
  description = "Name of the Elasticsearch domain"
  type        = string
  default     = "detector-gadget"
}

variable "elasticsearch_instance_type" {
  description = "Instance type for Elasticsearch nodes"
  type        = string
  default     = "t3.small.elasticsearch"
}

variable "elasticsearch_instance_count" {
  description = "Number of instances in the Elasticsearch domain"
  type        = number
  default     = 2
}

variable "elasticsearch_volume_size" {
  description = "Size in GB of EBS volumes for Elasticsearch"
  type        = number
  default     = 20
}

variable "elasticsearch_master_user" {
  description = "Master username for Elasticsearch"
  type        = string
  default     = "es-admin"
  sensitive   = true
}

variable "elasticsearch_master_password" {
  description = "Master password for Elasticsearch"
  type        = string
  sensitive   = true
}

# ------------------------------------------------------
# Database Configuration
# ------------------------------------------------------

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "detector_gadget"
}

variable "db_username" {
  description = "Username for the PostgreSQL database"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "db_password" {
  description = "Password for the PostgreSQL database"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "Instance class for the PostgreSQL database"
  type        = string
  default     = "db.t3.small"
}

variable "db_allocated_storage" {
  description = "Allocated storage for the PostgreSQL database in GB"
  type        = number
  default     = 20
}

# ------------------------------------------------------
# Redis Configuration
# ------------------------------------------------------

variable "redis_node_type" {
  description = "Node type for Redis"
  type        = string
  default     = "cache.t3.small"
}

# ------------------------------------------------------
# ECS Configuration
# ------------------------------------------------------

variable "web_app_cpu" {
  description = "CPU units for the web app task"
  type        = number
  default     = 512
}

variable "web_app_memory" {
  description = "Memory for the web app task in MB"
  type        = number
  default     = 1024
}

variable "worker_cpu" {
  description = "CPU units for the worker task"
  type        = number
  default     = 1024
}

variable "worker_memory" {
  description = "Memory for the worker task in MB"
  type        = number
  default     = 2048
}

variable "web_app_count" {
  description = "Number of web app task instances"
  type        = number
  default     = 2
}

variable "worker_count" {
  description = "Number of worker task instances"
  type        = number
  default     = 2
}

# ------------------------------------------------------
# App Configuration
# ------------------------------------------------------

variable "flask_secret_key" {
  description = "Secret key for Flask application"
  type        = string
  sensitive   = true
}

# ------------------------------------------------------
# SSL Certificate
# ------------------------------------------------------

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS"
  type        = string
  default     = ""
}
