#!/usr/bin/env python3
"""
Initialize the Celery worker with the Flask app context.
This ensures that all Celery tasks have access to the Flask app context,
database models, and configurations.
"""

import os
import sys
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

if __name__ == '__main__':
    logger.info("Initializing Celery worker with Flask app context")
    
    # Import the Flask app and utils module
    try:
        from app import app, db
        import utils
    except ImportError as e:
        logger.error(f"Failed to import required modules: {str(e)}")
        sys.exit(1)
    
    # Initialize the database if needed
    with app.app_context():
        try:
            db.create_all()
            logger.info("Database tables created if they didn't exist")
        except Exception as e:
            logger.error(f"Failed to create database tables: {str(e)}")
            sys.exit(1)
        
        # Initialize the utils module with app context
        try:
            utils.initialize()
            logger.info("Utils module initialized with app context")
        except Exception as e:
            logger.error(f"Failed to initialize utils module: {str(e)}")
            sys.exit(1)
    
    logger.info("Initialization complete")
