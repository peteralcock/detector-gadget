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
