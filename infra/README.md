# Detector Gadget - Terraform Deployment

This directory contains Terraform configuration for deploying the Detector Gadget eDiscovery and entity relationship analysis platform on AWS.

## Architecture

The deployment creates the following AWS infrastructure:

![Architecture Diagram](architecture-diagram.png)

- **VPC with public and private subnets** across two availability zones
- **S3 Buckets** for evidence storage, reports, and analysis artifacts
- **RDS PostgreSQL** for application database
- **Elasticsearch Domain** for entity indexing and relationship analysis
- **ECS Cluster** with Fargate for containerized application
- **Lambda Functions** for entity processing and POI graph generation
- **SQS Queue** for processing job coordination
- **Application Load Balancer** for web application access
- **CloudWatch** for monitoring and logging
- **IAM roles** for secure service access

## Prerequisites

1. AWS CLI configured with administrator access
2. Terraform v1.0.0 or newer
3. Docker installed locally
4. An S3 bucket for Terraform state (referenced in `main.tf`)
5. Docker images built for:
   - Web application (`Dockerfile.python`)
   - Worker (`Dockerfile.python` with different command)
   - Bulk Extractor (`Dockerfile.kali`)

## Deployment Steps

### 1. Initialize the Terraform configuration

```bash
terraform init
```

### 2. Create a `terraform.tfvars` file

Copy the example file and modify it with your settings:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to set secure passwords and customize resource sizes according to your needs.

### 3. Review the deployment plan

```bash
terraform plan
```

### 4. Apply the configuration

```bash
terraform apply
```

### 5. Build and push Docker images

After the infrastructure is created, build and push the Docker images to the created ECR repositories:

```bash
# Log in to ECR
aws ecr get-login-password --region $(terraform output -raw aws_region) | \
  docker login --username AWS --password-stdin $(terraform output -raw ecr_repositories | jq -r '.web_app' | cut -d'/' -f1)

# Build and push web app image
docker build -t $(terraform output -raw ecr_repositories | jq -r '.web_app') -f Dockerfile.python .
docker push $(terraform output -raw ecr_repositories | jq -r '.web_app')

# Build and push worker image
docker build -t $(terraform output -raw ecr_repositories | jq -r '.worker') -f Dockerfile.python .
docker push $(terraform output -raw ecr_repositories | jq -r '.worker')

# Build and push bulk_extractor image
docker build -t $(terraform output -raw ecr_repositories | jq -r '.bulk_extractor') -f Dockerfile.kali .
docker push $(terraform output -raw ecr_repositories | jq -r '.bulk_extractor')
```

### 6. Verify deployment

Visit the ALB URL provided in the output to access the web application:

```bash
echo "Application URL: http://$(terraform output -raw alb_dns_name)"
```

## Configuration Reference

### S3 Buckets

- **Evidence Bucket**: Stores uploaded evidence files
- **Reports Bucket**: Stores generated reports and POI graphs
- **Artifacts Bucket**: Stores intermediate analysis artifacts

### Elasticsearch

The deployment creates an Elasticsearch domain for entity indexing and relationship analysis.

Access the Kibana dashboard at:

```bash
echo "Kibana URL: $(terraform output -raw elasticsearch_dashboard)"
```

**Default indices:**

- `entities`: Stores extracted entities with their context and sentiment
- `relationships`: Stores relationships between entities

### Lambda Functions

- **Entity Processor**: Triggered by S3 uploads to extract entities and relationships
- **POI Graph Generator**: Generates relationship graphs on a daily schedule

### Entity Types

The system is configured to detect and index the following entity types:

- Email addresses
- Phone numbers
- URLs
- Credit card numbers
- IP addresses
- Usernames
- Social Security Numbers
- Domain names

## Entity Relationship Analysis

The system performs the following analyses:

1. **Entity extraction** from evidence files
2. **Sentiment analysis** to determine relationship polarity
3. **Relationship detection** between entities
4. **Entity centrality** to identify important entities
5. **Community detection** to find related entity groups
6. **POI graph visualization** to show entity networks

## Customization

### Adding New Entity Types

Edit the `PATTERNS` dictionary in `lambda/entity_processor.py` to add new entity types:

```python
PATTERNS = {
    'email': r'[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+',
    # Add your new entity type pattern here
    'new_type': r'your_regex_pattern'
}
```

### Modifying Graph Visualization 

Customize the POI graph visualization by editing `lambda/poi_graph_generator.py`:

- Edit `ENTITY_COLORS` to change entity type colors
- Modify `generate_network_visualization()` to adjust layout
- Edit `generate_sentiment_analysis()` to change sentiment categories

## Maintenance

### Backing Up Data

Schedule regular backups of:

1. RDS PostgreSQL database
   ```bash
   aws rds create-db-snapshot --db-instance-identifier $(terraform output -raw rds_endpoint | cut -d':' -f1) --db-snapshot-identifier manual-snapshot-$(date +%Y%m%d)
   ```

2. S3 evidence and reports
   ```bash
   aws s3 sync s3://$(terraform output -raw evidence_bucket) s3://your-backup-bucket/evidence/
   aws s3 sync s3://$(terraform output -raw reports_bucket) s3://your-backup-bucket/reports/
   ```

3. Elasticsearch indices (using Elasticsearch snapshots)

### Scaling

The infrastructure can be scaled by adjusting the following variables:

- `web_app_count`: Number of web application tasks
- `worker_count`: Number of worker tasks
- `elasticsearch_instance_count`: Number of Elasticsearch nodes
- `elasticsearch_instance_type`: Size of Elasticsearch nodes
- `db_instance_class`: RDS instance size

## Cleanup

To destroy all created resources:

```bash
terraform destroy
```

**Warning**: This will remove all data including evidence files, reports, and the database.

## Security Considerations

1. The `terraform.tfvars` file contains sensitive information - do not commit it to version control
2. Use strong, unique passwords for:
   - RDS PostgreSQL
   - Elasticsearch master user
   - Flask secret key
3. Consider encrypting the Terraform state file
4. Review and restrict the IAM roles to the minimum required permissions
5. Monitor CloudWatch logs for unusual activity
6. Enable AWS GuardDuty for threat detection

## Troubleshooting

### Common Issues

1. **Failed Lambda deployments**
   - Check Lambda logs in CloudWatch
   - Verify IAM roles have correct permissions

2. **Entity extraction not working**
   - Check SQS queue for stuck messages
   - Verify S3 notification configuration

3. **POI graph generation issues**
   - Check CloudWatch logs for the POI Graph Generator Lambda
   - Verify Elasticsearch has sufficient storage and instance capacity
