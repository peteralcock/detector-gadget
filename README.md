# Detector Gadget

Detector Gadget is an eDiscovery and digital forensics analysis tool to analyze digital artifacts and extract useful information for litigation.

## Features

- Web-based interface for submitting and managing analysis jobs
- Containerized architecture with Docker and Docker Compose
- Support for file uploads and remote file URL analysis
- Visualization of analysis results with interactive charts
- Background job processing with Celery
- RSpec testing suite for API endpoints
- Built using Flask, PostgreSQL, and Redis

## Architecture

The application consists of the following components:

1. **Web Application** (Flask): Handles user authentication, job submission, and result display
2. **Background Worker** (Celery): Processes jobs asynchronously
3. **Bulk Extractor** (Docker container): Performs the actual forensic analysis
4. **Database** (PostgreSQL): Stores user, job, and feature data
5. **Message Broker** (Redis): Facilitates communication between web app and workers

## Getting Started

### Prerequisites

- Docker and Docker Compose
- Git

### Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/detector-gadget.git
   cd detector-gadget
   ```

2. Start the services:
   ```
   docker-compose up -d
   ```

3. Initialize the database:
   ```
   curl http://localhost:5000/init_db
   ```

4. Access the application at http://localhost:5000
   - Default admin credentials: username `admin` / password `admin`

## Running Tests

The project includes RSpec tests for API endpoints:

```
rake test            # Run tests against a running application
rake docker_test     # Start Docker services, run tests, and stop services
```

## Development

For development, you can mount your local directory into the container:

```
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up
```
 
## Key Improvements

### 1. Code Structure and Organization

- **Fixed imports**: Eliminated circular imports by restructuring the code
- **Added proper error handling**: Added try/except blocks and logging throughout
- **Improved database models**: Added timestamps, more fields, and relationships
- **Enhanced user authentication**: Implemented registration, login, and session management

### 2. Docker Configuration

- **Kali Linux container**: Created a proper Dockerfile for bulk_extractor based on Kali Linux
- **Python application container**: Created a Python container with all necessary dependencies
- **Docker Compose setup**: Configured all services with proper volumes and networking
- **Entrypoint script**: Added an entrypoint script for proper initialization

### 3. UI/UX Improvements

- **Modern dashboard**: Redesigned the dashboard with Bootstrap and charts
- **Interactive job details**: Added detailed views for jobs with feature breakdowns
- **Form improvements**: Enhanced the job submission form with better UI
- **Data visualization**: Added Chart.js for data visualization

### 4. Feature Improvements

- **Enhanced job processing**: Improved file handling and error recovery
- **Better report generation**: Added detailed reports with statistics
- **API endpoints**: Added JSON API endpoints for retrieving job data
- **Visualization components**: Created React components for data visualization

### 5. Testing

- **RSpec tests**: Added comprehensive tests for all API endpoints
- **Test fixtures**: Created sample fixtures for testing
- **Rake tasks**: Added convenience tasks for running tests locally or in Docker

## Files Created or Modified

### Docker Configuration
- `Dockerfile.python`: Python application container
- `Dockerfile.kali`: Kali Linux container with bulk_extractor
- `docker-compose.yml`: Service orchestration
- `entrypoint.sh`: Container initialization

### Core Application
- `app.py`: Main Flask application (fixed)
- `utils.py`: Utility functions and Celery tasks (fixed)
- `celery_init.py`: Celery worker initialization
- `requirements.txt`: Python dependencies

### Templates
- `templates/dashboard.html`: Main dashboard with charts
- `templates/job_details.html`: Detailed job view
- `templates/login.html`: User login page
- `templates/register.html`: User registration page
- `templates/submit_job.html`: Job submission form

### Testing
- `spec/app_spec.rb`: RSpec tests for API endpoints
- `spec/spec_helper.rb`: Test configuration
- `Rakefile`: Rake tasks for testing

### Visualization
- React component: Feature distribution visualization

### Documentation
- `README.md`: Project documentation

## Technical Implementation Details

### Authentication System
- Uses Flask-Login for session management
- Passwords are securely hashed using Werkzeug's password hashing
- Protected routes require authentication

### Job Processing Pipeline
1. User submits a job through the web interface
2. Job is stored in PostgreSQL and queued with Celery
3. Celery worker picks up the job and processes it
4. bulk_extractor is run in a Docker container for forensic analysis
5. Results are parsed and stored in the database
6. Reports are generated and delivered

### Data Visualization
- Uses Chart.js for interactive charts
- Features both pie charts and bar charts for data visualization
- React component for advanced visualizations

### Security Considerations
- User authentication with password hashing
- Input validation for all user inputs
- Proper error handling to prevent information leakage
- Docker isolation for processing untrusted files

## Next Steps

1. **Add more scanners**: Integrate additional forensic tools
2. **Implement user roles**: Add admin and analyst roles
3. **Improve reporting**: Add PDF report generation
4. **Add file preview**: Add ability to preview file contents
5. **Implement case management**: Group jobs into cases for better organization

6. ## Issues

The original code had several issues that needed to be addressed:

1. **Circular imports**: The `process_job` Celery task was defined in utils.py but imported in app.py
2. **Missing imports**: Some modules like `os` were imported inside functions rather than at the module level
3. **Incomplete login system**: Missing routes for user authentication
4. **Missing user_loader decorator**: Required for Flask-Login to function properly
5. **Docker configuration issues**: No proper configuration for the main application or bulk_extractor
6. **Lack of error handling**: No proper error handling in the job processing flow
7. **No visualization**: No charting or visualization capabilities
