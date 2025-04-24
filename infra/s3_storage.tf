# ------------------------------------------------------
# S3 Buckets for Evidence, Reports, and Artifacts
# ------------------------------------------------------

resource "aws_s3_bucket" "evidence_bucket" {
  bucket = var.evidence_bucket_name
  force_destroy = false  # Prevents accidental deletion of evidence

  tags = {
    Name = "detector-gadget-evidence"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "reports_bucket" {
  bucket = var.reports_bucket_name
  force_destroy = false

  tags = {
    Name = "detector-gadget-reports"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "artifacts_bucket" {
  bucket = var.artifacts_bucket_name
  force_destroy = false

  tags = {
    Name = "detector-gadget-artifacts"
    Environment = var.environment
  }
}

# Apply bucket policies

resource "aws_s3_bucket_ownership_controls" "evidence_bucket_ownership" {
  bucket = aws_s3_bucket.evidence_bucket.id
  
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "evidence_bucket_public_access" {
  bucket = aws_s3_bucket.evidence_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "evidence_encryption" {
  bucket = aws_s3_bucket.evidence_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "evidence_lifecycle" {
  bucket = aws_s3_bucket.evidence_bucket.id

  rule {
    id = "evidence-retention"
    
    status = "Enabled"

    # Transition to Infrequent Access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Move to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Evidence should typically be kept for legal requirements
    # Adjust this based on your specific retention policy
    expiration {
      days = var.evidence_retention_days
    }
  }
}

# Apply similar policies to reports and artifacts buckets

resource "aws_s3_bucket_ownership_controls" "reports_bucket_ownership" {
  bucket = aws_s3_bucket.reports_bucket.id
  
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "reports_bucket_public_access" {
  bucket = aws_s3_bucket.reports_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports_encryption" {
  bucket = aws_s3_bucket.reports_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "artifacts_bucket_ownership" {
  bucket = aws_s3_bucket.artifacts_bucket.id
  
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts_bucket_public_access" {
  bucket = aws_s3_bucket.artifacts_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts_encryption" {
  bucket = aws_s3_bucket.artifacts_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ------------------------------------------------------
# IAM Roles and Policies for S3 Access
# ------------------------------------------------------

resource "aws_iam_role" "ecs_s3_access_role" {
  name = "detector-gadget-ecs-s3-access"

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

resource "aws_iam_policy" "s3_access_policy" {
  name        = "detector-gadget-s3-access-policy"
  description = "Policy for ECS tasks to access S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.evidence_bucket.arn,
          "${aws_s3_bucket.evidence_bucket.arn}/*",
          aws_s3_bucket.reports_bucket.arn,
          "${aws_s3_bucket.reports_bucket.arn}/*",
          aws_s3_bucket.artifacts_bucket.arn,
          "${aws_s3_bucket.artifacts_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_s3_policy_attachment" {
  role       = aws_iam_role.ecs_s3_access_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# ------------------------------------------------------
# S3 Notification for Entity Processing
# ------------------------------------------------------

resource "aws_sns_topic" "new_evidence_notification" {
  name = "detector-gadget-new-evidence"
}

resource "aws_s3_bucket_notification" "evidence_notification" {
  bucket = aws_s3_bucket.evidence_bucket.id

  topic {
    topic_arn     = aws_sns_topic.new_evidence_notification.arn
    events        = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic.new_evidence_notification]
}

resource "aws_iam_role" "lambda_s3_processor_role" {
  name = "detector-gadget-lambda-s3-processor"

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

resource "aws_iam_policy" "lambda_s3_processor_policy" {
  name        = "detector-gadget-lambda-s3-processor-policy"
  description = "Policy for Lambda to process S3 events and interact with other services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "sns:Subscribe",
          "sns:Receive",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage"
        ]
        Resource = [
          "${aws_s3_bucket.evidence_bucket.arn}/*",
          aws_sns_topic.new_evidence_notification.arn,
          "arn:aws:logs:*:*:*",
          "${aws_elasticsearch_domain.entity_graph.arn}/*",
          aws_sqs_queue.processing_queue.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_processor_attachment" {
  role       = aws_iam_role.lambda_s3_processor_role.name
  policy_arn = aws_iam_policy.lambda_s3_processor_policy.arn
}

resource "aws_sqs_queue" "processing_queue" {
  name                      = "detector-gadget-processing-queue"
  delay_seconds             = 0
  max_message_size          = 262144  # 256 KB
  message_retention_seconds = 86400   # 1 day
  receive_wait_time_seconds = 10      # Long polling

  tags = {
    Name = "detector-gadget-processing-queue"
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "evidence_to_queue" {
  topic_arn = aws_sns_topic.new_evidence_notification.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.processing_queue.arn
}
