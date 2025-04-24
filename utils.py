@celery.task
def process_job(job_id, file_path_or_url):
    job = Job.query.get(job_id)
    import requests
    import docker
    import os

    # Download file if URL is provided
    if file_path_or_url.startswith('http'):
        file_path = f'/tmp/job_{job_id}'
        response = requests.get(file_path_or_url)
        with open(file_path, 'wb') as f:
            f.write(response.content)
    else:
        file_path = file_path_or_url

    # Run bulk_extractor in Docker
    client = docker.from_env()
    output_dir = f'/tmp/output_{job_id}'
    os.makedirs(output_dir, exist_ok=True)
    client.containers.run(
        'bulk_extractor_image',
        command=f'-o /output /input/file',
        volumes={
            file_path: {'bind': '/input/file', 'mode': 'ro'},
            output_dir: {'bind': '/output', 'mode': 'rw'}
        },
        remove=True
    )

    # Parse output
    parse_feature_files(output_dir, job_id)

    # Generate and deliver report
    report_path = generate_report(job_id)
    deliver_report(job, report_path)
    job.status = 'completed'
    db.session.commit()

def generate_report(job_id):
    job = Job.query.get(job_id)
    features = Feature.query.filter_by(job_id=job_id).all()
    from collections import Counter
    feature_counts = Counter([f.feature_type for f in features])
    report = f"Report for Job {job_id}\n"
    report += f"Total features found: {len(features)}\n"
    for ftype, count in feature_counts.items():
        report += f"{ftype}: {count}\n"
    report_path = f'/tmp/report_{job_id}.txt'
    with open(report_path, 'w') as f:
        f.write(report)
    return report_path

def deliver_report(job, report_path):
    import requests
    import smtplib
    from email.mime.text import MIMEText
    output_dest = job.output_destination
    if output_dest.startswith('http'):  # Assume S3 presigned URL
        with open(report_path, 'rb') as f:
            requests.put(output_dest, data=f)
    elif '@' in output_dest:  # Assume email
        msg = MIMEText('See attached report', 'plain')
        msg['Subject'] = f'eDiscovery Report for Job {job.id}'
        msg['From'] = 'your_email@example.com'
        msg['To'] = output_dest
        with open(report_path, 'r') as f:
            msg.attach(MIMEText(f.read(), 'plain'))
        with smtplib.SMTP('smtp.example.com', 587) as server:
            server.starttls()
            server.login('your_email@example.com', 'your_password')
            server.send_message(msg)

def parse_feature_files(output_dir, job_id):
    for filename in os.listdir(output_dir):
        if filename.endswith('.txt'):
            feature_type = filename.split('.')[0]
            with open(os.path.join(output_dir, filename), 'r') as f:
                for line in f:
                    parts = line.strip().split('\t')
                    if len(parts) >= 2:
                        offset = parts[0]
                        value = parts[1]
                        context = parts[2] if len(parts) > 2 else ''
                        feature = Feature(job_id=job_id, feature_type=feature_type, value=value, offset=offset, context=context)
                        db.session.add(feature)
    db.session.commit()
