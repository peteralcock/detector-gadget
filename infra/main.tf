terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  backend "s3" {
    bucket = "detector-gadget-terraform-state"
    key    = "terraform/state"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------
# VPC and Networking
# ------------------------------------------------------

resource "aws_vpc" "detector_gadget_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "detector-gadget-vpc"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.detector_gadget_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "detector-gadget-public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.detector_gadget_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "detector-gadget-public-subnet-2"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.detector_gadget_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "detector-gadget-private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.detector_gadget_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "detector-gadget-private-subnet-2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.detector_gadget_vpc.id

  tags = {
    Name = "detector-gadget-igw"
  }
}

resource "aws_eip" "nat_eip_1" {
  domain = "vpc"
  
  tags = {
    Name = "detector-gadget-nat-eip-1"
  }
}

resource "aws_nat_gateway" "nat_gateway_1" {
  allocation_id = aws_eip.nat_eip_1.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "detector-gadget-nat-1"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.detector_gadget_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "detector-gadget-public-rt"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.detector_gadget_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway_1.id
  }

  tags = {
    Name = "detector-gadget-private-rt"
  }
}

resource "aws_route_table_association" "public_rta_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rta_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_rta_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

# ------------------------------------------------------
# Security Groups
# ------------------------------------------------------

resource "aws_security_group" "alb_sg" {
  name        = "detector-gadget-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.detector_gadget_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "detector-gadget-alb-sg"
  }
}

resource "aws_security_group" "ecs_sg" {
  name        = "detector-gadget-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.detector_gadget_vpc.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "detector-gadget-ecs-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "detector-gadget-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = aws_vpc.detector_gadget_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "detector-gadget-rds-sg"
  }
}

resource "aws_security_group" "redis_sg" {
  name        = "detector-gadget-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = aws_vpc.detector_gadget_vpc.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "detector-gadget-redis-sg"
  }
}

resource "aws_security_group" "es_sg" {
  name        = "detector-gadget-es-sg"
  description = "Security group for Elasticsearch"
  vpc_id      = aws_vpc.detector_gadget_vpc.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "detector-gadget-es-sg"
  }
}
