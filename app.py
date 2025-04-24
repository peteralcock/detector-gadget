from flask import Flask, render_template, request, redirect, url_for
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from flask_sqlalchemy import SQLAlchemy
from celery import Celery
import os

app = Flask(__name__)
app.config['SECRET_KEY'] = 'your_secret_key'
app.config['SQLALCHEMY_DATABASE_URI'] = 'postgresql://user:password@localhost/ediscovery'
app.config['CELERY_BROKER_URL'] = 'redis://localhost:6379/0'
app.config['CELERY_RESULT_BACKEND'] = 'redis://localhost:6379/0'

db = SQLAlchemy(app)
login_manager = LoginManager(app)
celery = Celery(app.name, broker=app.config['CELERY_BROKER_URL'])
celery.conf.update(app.config)

class User(db.Model, UserMixin):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password = db.Column(db.String(120), nullable=False)

class Job(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    status = db.Column(db.String(20), default='pending')
    input_source = db.Column(db.String(255))
    output_destination = db.Column(db.String(255))

class Feature(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    job_id = db.Column(db.Integer, db.ForeignKey('job.id'), nullable=False)
    feature_type = db.Column(db.String(50))
    value = db.Column(db.String(255))
    offset = db.Column(db.BigInteger)
    context = db.Column(db.Text)

@app.route('/submit_job', methods=['GET', 'POST'])
@login_required
def submit_job():
    if request.method == 'POST':
        file = request.files.get('file')
        url = request.form.get('url')
        output_dest = request.form.get('output_dest')
        input_source = url if url else 'upload'
        job = Job(user_id=current_user.id, input_source=input_source, output_destination=output_dest)
        db.session.add(job)
        db.session.commit()
        if file:
            file_path = os.path.join('/tmp', f'job_{job.id}')
            file.save(file_path)
        process_job.delay(job.id, file_path if file else url)
        return redirect(url_for('dashboard'))
    return render_template('submit_job.html')
