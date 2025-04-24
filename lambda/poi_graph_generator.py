import os
import json
import boto3
import logging
import requests
import uuid
import networkx as nx
from datetime import datetime, timedelta
from requests.auth import HTTPBasicAuth
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
from io import BytesIO

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize clients
s3 = boto3.client('s3')

# Get environment variables
ES_ENDPOINT = os.environ['ELASTICSEARCH_ENDPOINT']
ES_USERNAME = os.environ['ELASTICSEARCH_USERNAME']
ES_PASSWORD = os.environ['ELASTICSEARCH_PASSWORD']
REPORTS_BUCKET = os.environ['REPORTS_BUCKET']

# Entity type colors for visualization
ENTITY_COLORS = {
    'email': '#3498db',     # Blue
    'phone': '#2ecc71',     # Green
    'url': '#9b59b6',       # Purple
    'credit_card': '#e74c3c', # Red
    'ip_address': '#f39c12', # Orange
    'username': '#1abc9c',  # Turquoise
    'ssn': '#e67e22',       # Dark Orange
    'domain': '#34495e'     # Dark Blue
}

def handler(event, context):
    """Generate POI relationship graphs from entity data in Elasticsearch"""
    logger.info("Starting POI graph generation")
    
    try:
        # Query relationships from Elasticsearch
        relationships = query_relationships()
        
        if not relationships:
            logger.info("No relationships found to generate graphs")
            return {
                'statusCode': 200,
                'body': json.dumps('No relationships found')
            }
        
        # Build graph from relationships
        graph = build_graph(relationships)
        
        # Generate various graph analyses
        generate_graph_analyses(graph, relationships)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Graph generation complete')
        }
    
    except Exception as e:
        logger.error(f"Error generating POI graphs: {str(e)}")
        raise

def query_relationships(days=30, min_strength=1):
    """Query entity relationships from Elasticsearch"""
    auth = HTTPBasicAuth(ES_USERNAME, ES_PASSWORD)
    
    # Calculate date range
    end_date = datetime.utcnow()
    start_date = end_date - timedelta(days=days)
    
    # Build query
    query = {
        "size": 10000,  # Adjust based on expected volume
        "query": {
            "bool": {
                "must": [
                    {
                        "range": {
                            "processed_at": {
                                "gte": start_date.isoformat(),
                                "lte": end_date.isoformat()
                            }
                        }
                    },
                    {
                        "range": {
                            "strength": {
                                "gte": min_strength
                            }
                        }
                    }
                ]
            }
        }
    }
    
    try:
        # Query Elasticsearch
        url = f"{ES_ENDPOINT}/relationships/_search"
        response = requests.post(
            url,
            json=query,
            auth=auth,
            headers={"Content-Type": "application/json"}
        )
        response.raise_for_status()
        
        results = response.json()
        relationships = [hit['_source'] for hit in results.get('hits', {}).get('hits', [])]
        
        logger.info(f"Retrieved {len(relationships)} relationships from Elasticsearch")
        return relationships
    
    except Exception as e:
        logger.error(f"Error querying relationships from Elasticsearch: {str(e)}")
        return []

def build_graph(relationships):
    """Build a NetworkX graph from relationships"""
    G = nx.Graph()
    
    # Add nodes and edges
    for rel in relationships:
        source_type = rel['source']['type']
        source_value = rel['source']['value']
        target_type = rel['target']['type']
        target_value = rel['target']['value']
        
        # Add nodes with attributes
        if not G.has_node(source_value):
            G.add_node(source_value, type=source_type)
        
        if not G.has_node(target_value):
            G.add_node(target_value, type=target_type)
        
        # Add edge with attributes
        G.add_edge(
            source_value, 
            target_value, 
            weight=rel['strength'],
            sentiment=rel['sentiment']
        )
    
    logger.info(f"Built graph with {G.number_of_nodes()} nodes and {G.number_of_edges()} edges")
    return G

def generate_graph_analyses(graph, relationships):
    """Generate various graph analyses and visualizations"""
    timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    report_data = {
        'generated_at': datetime.utcnow().isoformat(),
        'graph_stats': {
            'nodes': graph.number_of_nodes(),
            'edges': graph.number_of_edges(),
            'connected_components': nx.number_connected_components(graph),
            'density': nx.density(graph)
        },
        'centrality_measures': {},
        'communities': [],
        'visualizations': []
    }
    
    # 1. Calculate centrality measures
    degree_centrality = nx.degree_centrality(graph)
    betweenness_centrality = nx.betweenness_centrality(graph)
    eigenvector_centrality = nx.eigenvector_centrality(graph, max_iter=1000)
    
    # Add to report data
    report_data['centrality_measures'] = {
        'degree_centrality': {node: round(value, 4) for node, value in sorted(degree_centrality.items(), key=lambda x: x[1], reverse=True)[:20]},
        'betweenness_centrality': {node: round(value, 4) for node, value in sorted(betweenness_centrality.items(), key=lambda x: x[1], reverse=True)[:20]},
        'eigenvector_centrality': {node: round(value, 4) for node, value in sorted(eigenvector_centrality.items(), key=lambda x: x[1], reverse=True)[:20]}
    }
    
    # 2. Community detection
    try:
        communities = list(nx.community.greedy_modularity_communities(graph))
        
        # Add to report data
        report_data['communities'] = [
            {'id': i, 'size': len(community), 'members': list(community)[:20]}
            for i, community in enumerate(communities)
        ]
        
        # 3. Generate community visualization
        vis_files = []
        
        # 3.1 Overall network visualization
        file_path = generate_network_visualization(graph, f"full_network_{timestamp}.png")
        if file_path:
            vis_files.append({
                'type': 'full_network',
                'file_path': file_path,
                'node_count': graph.number_of_nodes(),
                'edge_count': graph.number_of_edges()
            })
        
        # 3.2 Top communities visualization
        for i, community in enumerate(communities[:5]):  # Visualize top 5 communities
            if len(community) > 2:  # Only visualize communities with at least 3 members
                subgraph = graph.subgraph(community)
                file_path = generate_network_visualization(
                    subgraph, 
                    f"community_{i}_{timestamp}.png",
                    title=f"Community {i} - {len(community)} members"
                )
                if file_path:
                    vis_files.append({
                        'type': 'community',
                        'community_id': i,
                        'file_path': file_path,
                        'node_count': subgraph.number_of_nodes(),
                        'edge_count': subgraph.number_of_edges()
                    })
        
        # 3.3 Ego networks for top central nodes
        top_nodes = sorted(degree_centrality.items(), key=lambda x: x[1], reverse=True)[:5]
        for node, centrality in top_nodes:
            ego_network = nx.ego_graph(graph, node, radius=1)
            if ego_network.number_of_nodes() > 2:
                file_path = generate_network_visualization(
                    ego_network,
                    f"ego_network_{node[:20]}_{timestamp}.png",
                    title=f"Connections for {node[:20]}"
                )
                if file_path:
                    vis_files.append({
                        'type': 'ego_network',
                        'central_node': node,
                        'file_path': file_path,
                        'node_count': ego_network.number_of_nodes(),
                        'edge_count': ego_network.number_of_edges()
                    })
        
        report_data['visualizations'] = vis_files
        
    except Exception as e:
        logger.error(f"Error generating community detection and visualization: {str(e)}")
    
    # 4. Generate sentiment analysis
    generate_sentiment_analysis(graph, relationships, report_data, timestamp)
    
    # 5. Store report data
    report_key = f"graphs/poi_graph_analysis_{timestamp}.json"
    try:
        s3.put_object(
            Bucket=REPORTS_BUCKET,
            Key=report_key,
            Body=json.dumps(report_data, indent=2),
            ContentType='application/json'
        )
        logger.info(f"Stored POI graph analysis report at {REPORTS_BUCKET}/{report_key}")
    except Exception as e:
        logger.error(f"Error storing POI graph analysis report: {str(e)}")

def generate_network_visualization(graph, filename, title=None):
    """Generate network visualization and save to S3"""
    try:
        plt.figure(figsize=(12, 8))
        
        # Get node colors based on type
        node_colors = [
            ENTITY_COLORS.get(graph.nodes[node].get('type'), '#cccccc')
            for node in graph.nodes()
        ]
        
        # Get edge weights for thickness
        edge_weights = [graph[u][v].get('weight', 1) for u, v in graph.edges()]
        
        # Get node sizes based on degree centrality
        node_degrees = dict(graph.degree())
        node_sizes = [50 + 10 * node_degrees[node] for node in graph.nodes()]
        
        # Create layout
        if graph.number_of_nodes() < 100:
            pos = nx.spring_layout(graph, k=0.3, iterations=50)
        else:
            pos = nx.kamada_kawai_layout(graph)
        
        # Draw network
        nx.draw_networkx_nodes(graph, pos, node_size=node_sizes, node_color=node_colors, alpha=0.8)
        nx.draw_networkx_edges(graph, pos, width=edge_weights, alpha=0.5, edge_color='#999999')
        
        # Add labels for smaller graphs
        if graph.number_of_nodes() < 50:
            # Create abbreviated labels for readability
            labels = {}
            for node in graph.nodes():
                if isinstance(node, str) and len(node) > 20:
                    node_type = graph.nodes[node].get('type', '')
                    if node_type == 'email':
                        # Show username part of email
                        username = node.split('@')[0]
                        labels[node] = username
                    else:
                        # Truncate long labels
                        labels[node] = node[:17] + "..."
                else:
                    labels[node] = node
            
            nx.draw_networkx_labels(graph, pos, labels=labels, font_size=8, font_color='black')
        
        # Add title if provided
        if title:
            plt.title(title)
        
        # Add legend for entity types
        entity_types = set(nx.get_node_attributes(graph, 'type').values())
        if entity_types:
            handles = []
            for entity_type in sorted(entity_types):
                color = ENTITY_COLORS.get(entity_type, '#cccccc')
                handles.append(plt.Line2D([0], [0], marker='o', color='w', markerfacecolor=color, markersize=10, label=entity_type))
            
            plt.legend(handles=handles, loc='best')
        
        # Remove axis
        plt.axis('off')
        
        # Save figure to memory and upload to S3
        buf = BytesIO()
        plt.savefig(buf, format='png', dpi=300, bbox_inches='tight')
        buf.seek(0)
        
        # Upload to S3
        s3_key = f"graphs/{filename}"
        s3.put_object(
            Bucket=REPORTS_BUCKET,
            Key=s3_key,
            Body=buf.getvalue(),
            ContentType='image/png'
        )
        
        plt.close()
        logger.info(f"Saved network visualization to {REPORTS_BUCKET}/{s3_key}")
        return s3_key
    
    except Exception as e:
        logger.error(f"Error generating network visualization: {str(e)}")
        plt.close()
        return None

def generate_sentiment_analysis(graph, relationships, report_data, timestamp):
    """Generate sentiment analysis for entity relationships"""
    try:
        # Create sentiment distribution data
        sentiment_ranges = {
            'very_negative': {'min': -1.0, 'max': -0.6, 'count': 0},
            'negative': {'min': -0.6, 'max': -0.2, 'count': 0},
            'neutral': {'min': -0.2, 'max': 0.2, 'count': 0},
            'positive': {'min': 0.2, 'max': 0.6, 'count': 0},
            'very_positive': {'min': 0.6, 'max': 1.0, 'count': 0}
        }
        
        # Count relationships in each sentiment range
        for rel in relationships:
            sentiment = rel['sentiment']
            for range_name, range_data in sentiment_ranges.items():
                if range_data['min'] <= sentiment < range_data['max'] or \
                   (range_name == 'very_positive' and sentiment == 1.0):
                    range_data['count'] += 1
                    break
        
        # Add sentiment distribution to report
        report_data['sentiment_analysis'] = {
            'distribution': {name: data['count'] for name, data in sentiment_ranges.items()},
            'overall_average': sum(rel['sentiment'] for rel in relationships) / len(relationships) if relationships else 0
        }
        
        # Generate entity pairs with strongest positive/negative sentiment
        sentiment_sorted = sorted(relationships, key=lambda x: x['sentiment'])
        
        # Most negative relationships
        most_negative = sentiment_sorted[:10] if len(sentiment_sorted) >= 10 else sentiment_sorted
        report_data['sentiment_analysis']['most_negative'] = [
            {
                'source': rel['source']['value'],
                'source_type': rel['source']['type'],
                'target': rel['target']['value'],
                'target_type': rel['target']['type'],
                'sentiment': rel['sentiment'],
                'strength': rel['strength']
            }
            for rel in most_negative
        ]
        
        # Most positive relationships
        most_positive = sentiment_sorted[-10:] if len(sentiment_sorted) >= 10 else []
        most_positive.reverse()  # Reverse to get highest first
        report_data['sentiment_analysis']['most_positive'] = [
            {
                'source': rel['source']['value'],
                'source_type': rel['source']['type'],
                'target': rel['target']['value'],
                'target_type': rel['target']['type'],
                'sentiment': rel['sentiment'],
                'strength': rel['strength']
            }
            for rel in most_positive
        ]
        
        # Generate sentiment visualization
        plt.figure(figsize=(10, 6))
        
        # Sentiment distribution bar chart
        categories = list(sentiment_ranges.keys())
        values = [sentiment_ranges[cat]['count'] for cat in categories]
        
        colors = ['#e74c3c', '#f39c12', '#95a5a6', '#2ecc71', '#27ae60']
        plt.bar(categories, values, color=colors)
        
        plt.title('Sentiment Distribution in Entity Relationships')
        plt.xlabel('Sentiment Category')
        plt.ylabel('Number of Relationships')
        
        # Save figure to memory and upload to S3
        buf = BytesIO()
        plt.savefig(buf, format='png', dpi=300, bbox_inches='tight')
        buf.seek(0)
        
        # Upload to S3
        s3_key = f"graphs/sentiment_distribution_{timestamp}.png"
        s3.put_object(
            Bucket=REPORTS_BUCKET,
            Key=s3_key,
            Body=buf.getvalue(),
            ContentType='image/png'
        )
        
        plt.close()
        logger.info(f"Saved sentiment visualization to {REPORTS_BUCKET}/{s3_key}")
        
        # Add visualization to report
        report_data['visualizations'].append({
            'type': 'sentiment_distribution',
            'file_path': s3_key
        })
        
    except Exception as e:
        logger.error(f"Error generating sentiment analysis: {str(e)}")
        plt.close()
