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
