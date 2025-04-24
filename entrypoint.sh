#!/bin/bash
set -e

# Initialize the database and Celery context
python celery_init.py

# Start the specified service
if [ "$1" = "web" ]; then
    echo "Starting web server..."
    exec python app.py
elif [ "$1" = "worker" ]; then
    echo "Starting Celery worker..."
    exec celery -A app.celery worker --loglevel=info
elif [ "$1" = "init" ]; then
    echo "Running initialization only"
    exit 0
else
    echo "Unknown service: $1"
    echo "Usage: $0 web|worker|init"
    exit 1
fi
