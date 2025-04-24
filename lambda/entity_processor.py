import os
import json
import boto3
import logging
import requests
import re
import uuid
from datetime import datetime
from botocore.exceptions import ClientError
from urllib.parse import unquote_plus
from requests.auth import HTTPBasicAuth
import nltk
from nltk.sentiment import SentimentIntensityAnalyzer

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Download NLTK resources
nltk.download('punkt', download_dir='/tmp')
nltk.download('vader_lexicon', download_dir='/tmp')
nltk.data.path.append('/tmp')

# Initialize clients
s3 = boto3.client('s3')
sqs = boto3.client('sqs')

# Get environment variables
ES_ENDPOINT = os.environ['ELASTICSEARCH_ENDPOINT']
ES_USERNAME = os.environ['ELASTICSEARCH_USERNAME']
ES_PASSWORD = os.environ['ELASTICSEARCH_PASSWORD']
EVIDENCE_BUCKET = os.environ['EVIDENCE_BUCKET']
ARTIFACTS_BUCKET = os.environ['ARTIFACTS_BUCKET']

# Entity patterns
PATTERNS = {
    'email': r'[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+',
    'phone': r'(?:\+\d{1,2}\s)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}',
    'url': r'https?://(?:[-\w.]|(?:%[\da-fA-F]{2}))+[/\w\.-]*(?:\?[\w=&.]+)?',
    'credit_card': r'\b(?:\d{4}[- ]?){3}\d{4}\b',
    'ip_address': r'\b(?:\d{1,3}\.){3}\d{1,3}\b',
    'username': r'@\w+',
    'ssn': r'\b\d{3}[-]?\d{2}[-]?\d{4}\b',
    'domain': r'\b(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}\b'
}

def handler(event, context):
    """Process SQS messages with S3 events, extract entities, and index to Elasticsearch"""
    logger.info("Received event: %s", json.dumps(event))
    
    # Initialize sentiment analyzer
    sia = SentimentIntensityAnalyzer()
    
    # Process each SQS message
    for record in event['Records']:
        try:
            # Parse SQS message body
            body = json.loads(record['body'])
            
            # Check if this is an S3 event notification
            if 'Records' in body and body.get('Records'):
                for s3_record in body['Records']:
                    if s3_record.get('eventSource') == 'aws:s3' and s3_record.get('eventName').startswith('ObjectCreated'):
                        bucket = s3_record['s3']['bucket']['name']
                        key = unquote_plus(s3_record['s3']['object']['key'])
                        
                        logger.info(f"Processing S3 object: {bucket}/{key}")
                        
                        # Process the file content
                        process_file(bucket, key, sia)
            
        except Exception as e:
            logger.error(f"Error processing message: {str(e)}")
            continue
    
    return {
        'statusCode': 200,
        'body': json.dumps('Processing complete')
    }

def process_file(bucket, key, sia):
    """Process a file from S3 to extract and index entities"""
    try:
        # Get file metadata
        metadata = s3.head_object(Bucket=bucket, Key=key)
        content_type = metadata.get('ContentType', 'application/octet-stream')
        
        # Get file content
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8', errors='replace')
        
        # Extract entities
        entities = extract_entities(content)
        
        # Add context and sentiment analysis
        enrich_entities(entities, content, sia)
        
        # Generate relationships between entities
        relationships = generate_relationships(entities)
        
        # Index entities to Elasticsearch
        index_entities(entities, bucket, key, metadata)
        
        # Index relationships to Elasticsearch
        index_relationships(relationships, bucket, key)
        
        # Create and store artifact with analysis results
        store_analysis_results(entities, relationships, bucket, key)
        
        logger.info(f"Successfully processed {bucket}/{key}")
        
    except Exception as e:
        logger.error(f"Error processing file {bucket}/{key}: {str(e)}")
        raise

def extract_entities(content):
    """Extract various entity types from content using regex patterns"""
    entities = {}
    
    # Apply each regex pattern to extract entities
    for entity_type, pattern in PATTERNS.items():
        matches = re.findall(pattern, content)
        if matches:
            # Deduplicate and normalize
            unique_matches = []
            for match in matches:
                normalized = normalize_entity(entity_type, match)
                if normalized and normalized not in unique_matches:
                    unique_matches.append(normalized)
            
            if unique_matches:
                entities[entity_type] = unique_matches
    
    return entities

def normalize_entity(entity_type, value):
    """Normalize entities based on their type"""
    if not value:
        return None
        
    value = value.strip()
    
    if entity_type == 'email':
        return value.lower()
    elif entity_type == 'phone':
        # Keep only digits
        digits = re.sub(r'\D', '', value)
        if len(digits) >= 10:
            return digits
        return None
    elif entity_type == 'credit_card':
        # Keep only digits
        digits = re.sub(r'\D', '', value)
        # Very basic validation - should be improved in production
        if len(digits) >= 15 and len(digits) <= 16:
            return digits
        return None
    elif entity_type == 'domain':
        return value.lower()
    # Add more normalization as needed
    
    return value

def enrich_entities(entities, content, sia):
    """Enrich entities with context and sentiment analysis"""
    # Split content into sentences
    sentences = nltk.sent_tokenize(content)
    
    # Process each entity type
    for entity_type, values in entities.items():
        enriched_values = []
        
        for value in values:
            entity_info = {
                'value': value,
                'occurrences': [],
                'sentiment': {'positive': 0, 'negative': 0, 'neutral': 0},
                'average_sentiment': 0
            }
            
            # Find occurrences in sentences
            for i, sentence in enumerate(sentences):
                if value in sentence:
                    # Get surrounding context (up to 3 sentences)
                    start_idx = max(0, i-1)
                    end_idx = min(len(sentences), i+2)
                    context = ' '.join(sentences[start_idx:end_idx])
                    
                    # Calculate sentiment
                    sentiment_scores = sia.polarity_scores(sentence)
                    sentiment_category = 'neutral'
                    if sentiment_scores['compound'] >= 0.05:
                        sentiment_category = 'positive'
                    elif sentiment_scores['compound'] <= -0.05:
                        sentiment_category = 'negative'
                    
                    # Increment sentiment counter
                    entity_info['sentiment'][sentiment_category] += 1
                    
                    # Record occurrence
                    entity_info['occurrences'].append({
                        'context': context,
                        'sentence_index': i,
                        'sentiment': sentiment_scores
                    })
            
            # Calculate average sentiment
            if entity_info['occurrences']:
                total_sentiment = sum(occ['sentiment']['compound'] for occ in entity_info['occurrences'])
                entity_info['average_sentiment'] = total_sentiment / len(entity_info['occurrences'])
            
            enriched_values.append(entity_info)
        
        # Replace original list with enriched information
        entities[entity_type] = enriched_values
    
    return entities

def generate_relationships(entities):
    """Generate relationships between different entity types"""
    relationships = []
    
    # Look for co-occurrences in the same contexts
    entity_contexts = {}
    
    # First, build a map of sentence indices to entities
    for entity_type, values in entities.items():
        for entity_idx, entity_info in enumerate(values):
            for occurrence in entity_info['occurrences']:
                sentence_idx = occurrence['sentence_index']
                if sentence_idx not in entity_contexts:
                    entity_contexts[sentence_idx] = []
                
                entity_contexts[sentence_idx].append({
                    'type': entity_type,
                    'value': entity_info['value'],
                    'entity_idx': entity_idx,
                    'sentiment': occurrence['sentiment']['compound']
                })
    
    # Then find relationships in the same contexts
    for sentence_idx, context_entities in entity_contexts.items():
        for i, entity1 in enumerate(context_entities):
            for j in range(i+1, len(context_entities)):
                entity2 = context_entities[j]
                
                # Skip if same entity type (except for emails which might be related)
                if entity1['type'] == entity2['type'] and entity1['type'] != 'email':
                    continue
                
                # Create relationship
                relationship = {
                    'source': {
                        'type': entity1['type'],
                        'value': entity1['value']
                    },
                    'target': {
                        'type': entity2['type'],
                        'value': entity2['value']
                    },
                    'context_indices': [sentence_idx],
                    'strength': 1,  # Will be incremented for multiple co-occurrences
                    'sentiment': (entity1['sentiment'] + entity2['sentiment']) / 2
                }
                
                # Check if relationship already exists
                existing = next((r for r in relationships if 
                                (r['source']['type'] == relationship['source']['type'] and
                                 r['source']['value'] == relationship['source']['value'] and
                                 r['target']['type'] == relationship['target']['type'] and
                                 r['target']['value'] == relationship['target']['value']) or
                                (r['source']['type'] == relationship['target']['type'] and
                                 r['source']['value'] == relationship['target']['value'] and
                                 r['target']['type'] == relationship['source']['type'] and
                                 r['target']['value'] == relationship['source']['value'])), None)
                
                if existing:
                    # Update existing relationship
                    if sentence_idx not in existing['context_indices']:
                        existing['context_indices'].append(sentence_idx)
                        existing['strength'] += 1
                        # Update average sentiment
                        total_sentiment = existing['sentiment'] * (len(existing['context_indices']) - 1)
                        total_sentiment += (entity1['sentiment'] + entity2['sentiment']) / 2
                        existing['sentiment'] = total_sentiment / len(existing['context_indices'])
                else:
                    # Add new relationship
                    relationships.append(relationship)
    
    return relationships

def index_entities(entities, bucket, key, metadata):
    """Index extracted entities to Elasticsearch"""
    timestamp = datetime.utcnow().isoformat()
    
    # Prepare the ES auth
    auth = HTTPBasicAuth(ES_USERNAME, ES_PASSWORD)
    
    # Create ES indices if they don't exist
    create_indices(auth)
    
    # Prepare document metadata
    doc_metadata = {
        'source_bucket': bucket,
        'source_key': key,
        'content_type': metadata.get('ContentType', 'unknown'),
        'last_modified': metadata.get('LastModified', datetime.utcnow()).isoformat(),
        'etag': metadata.get('ETag', '').strip('"'),
        'size': metadata.get('ContentLength', 0),
        'processed_at': timestamp
    }
    
    # Index each entity
    for entity_type, values in entities.items():
        for entity_info in values:
            # Prepare document ID based on entity type and value
            doc_id = f"{entity_type}_{hash(entity_info['value'])}"
            
            # Prepare entity document
            doc = {
                'entity_type': entity_type,
                'value': entity_info['value'],
                'processed_at': timestamp,
                'metadata': doc_metadata,
                'occurrences': entity_info['occurrences'],
                'sentiment': entity_info['sentiment'],
                'average_sentiment': entity_info['average_sentiment']
            }
            
            # Index to Elasticsearch
            try:
                url = f"{ES_ENDPOINT}/entities/_doc/{doc_id}"
                response = requests.put(
                    url,
                    json=doc,
                    auth=auth,
                    headers={"Content-Type": "application/json"}
                )
                response.raise_for_status()
                logger.info(f"Indexed entity: {entity_type}/{entity_info['value']}")
                
            except Exception as e:
                logger.error(f"Error indexing entity to Elasticsearch: {str(e)}")

def index_relationships(relationships, bucket, key):
    """Index entity relationships to Elasticsearch"""
    timestamp = datetime.utcnow().isoformat()
    
    # Prepare the ES auth
    auth = HTTPBasicAuth(ES_USERNAME, ES_PASSWORD)
    
    # Index each relationship
    for relationship in relationships:
        # Generate a unique ID for the relationship
        source_hash = hash(f"{relationship['source']['type']}_{relationship['source']['value']}")
        target_hash = hash(f"{relationship['target']['type']}_{relationship['target']['value']}")
        rel_id = f"rel_{min(source_hash, target_hash)}_{max(source_hash, target_hash)}"
        
        # Prepare relationship document
        doc = {
            'source': relationship['source'],
            'target': relationship['target'],
            'context_indices': relationship['context_indices'],
            'strength': relationship['strength'],
            'sentiment': relationship['sentiment'],
            'processed_at': timestamp,
            'source_document': {
                'bucket': bucket,
                'key': key
            }
        }
        
        # Index to Elasticsearch
        try:
            url = f"{ES_ENDPOINT}/relationships/_doc/{rel_id}"
            response = requests.put(
                url,
                json=doc,
                auth=auth,
                headers={"Content-Type": "application/json"}
            )
            response.raise_for_status()
            logger.info(f"Indexed relationship: {relationship['source']['value']} - {relationship['target']['value']}")
            
        except Exception as e:
            logger.error(f"Error indexing relationship to Elasticsearch: {str(e)}")

def create_indices(auth):
    """Create Elasticsearch indices if they don't exist"""
    indices = ['entities', 'relationships']
    
    for index in indices:
        try:
            # Check if index exists
            url = f"{ES_ENDPOINT}/{index}"
            response = requests.head(url, auth=auth)
            
            if response.status_code == 404:
                # Create index
                mapping = get_index_mapping(index)
                create_response = requests.put(
                    url,
                    json=mapping,
                    auth=auth,
                    headers={"Content-Type": "application/json"}
                )
                create_response.raise_for_status()
                logger.info(f"Created Elasticsearch index: {index}")
        
        except Exception as e:
            logger.error(f"Error creating Elasticsearch index {index}: {str(e)}")

def get_index_mapping(index):
    """Get index mapping based on index type"""
    if index == 'entities':
        return {
            "mappings": {
                "properties": {
                    "entity_type": {"type": "keyword"},
                    "value": {"type": "keyword"},
                    "processed_at": {"type": "date"},
                    "metadata": {
                        "properties": {
                            "source_bucket": {"type": "keyword"},
                            "source_key": {"type": "keyword"},
                            "content_type": {"type": "keyword"},
                            "last_modified": {"type": "date"},
                            "etag": {"type": "keyword"},
                            "size": {"type": "long"},
                            "processed_at": {"type": "date"}
                        }
                    },
                    "occurrences": {
                        "properties": {
                            "context": {"type": "text"},
                            "sentence_index": {"type": "integer"},
                            "sentiment": {
                                "properties": {
                                    "compound": {"type": "float"},
                                    "pos": {"type": "float"},
                                    "neg": {"type": "float"},
                                    "neu": {"type": "float"}
                                }
                            }
                        }
                    },
                    "sentiment": {
                        "properties": {
                            "positive": {"type": "integer"},
                            "negative": {"type": "integer"},
                            "neutral": {"type": "integer"}
                        }
                    },
                    "average_sentiment": {"type": "float"}
                }
            }
        }
    elif index == 'relationships':
        return {
            "mappings": {
                "properties": {
                    "source": {
                        "properties": {
                            "type": {"type": "keyword"},
                            "value": {"type": "keyword"}
                        }
                    },
                    "target": {
                        "properties": {
                            "type": {"type": "keyword"},
                            "value": {"type": "keyword"}
                        }
                    },
                    "context_indices": {"type": "integer"},
                    "strength": {"type": "integer"},
                    "sentiment": {"type": "float"},
                    "processed_at": {"type": "date"},
                    "source_document": {
                        "properties": {
                            "bucket": {"type": "keyword"},
                            "key": {"type": "keyword"}
                        }
                    }
                }
            }
        }
    
    return {}

def store_analysis_results(entities, relationships, bucket, key):
    """Store analysis results as a JSON artifact in S3"""
    analysis_results = {
        'source': {
            'bucket': bucket,
            'key': key
        },
        'processed_at': datetime.utcnow().isoformat(),
        'entities': entities,
        'relationships': relationships,
        'summary': {
            'entity_counts': {entity_type: len(values) for entity_type, values in entities.items()},
            'relationship_count': len(relationships)
        }
    }
    
    # Create artifact key
    source_key_parts = key.split('/')
    filename = source_key_parts[-1]
    artifact_key = f"analysis/{filename}_analysis_{uuid.uuid4()}.json"
    
    # Store artifact in S3
    try:
        s3.put_object(
            Bucket=ARTIFACTS_BUCKET,
            Key=artifact_key,
            Body=json.dumps(analysis_results, indent=2),
            ContentType='application/json'
        )
        logger.info(f"Stored analysis results to {ARTIFACTS_BUCKET}/{artifact_key}")
    
    except Exception as e:
        logger.error(f"Error storing analysis results: {str(e)}")
