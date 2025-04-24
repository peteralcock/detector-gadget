require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
end

task :default => :spec

desc 'Run RSpec tests against running application'
task :test do
  puts "Running tests against application"
  sh "rspec spec"
end

desc 'Run RSpec tests against Docker application'
task :docker_test do
  puts "Starting Docker services for testing"
  sh "docker-compose up -d"
  puts "Waiting 10 seconds for services to start..."
  sleep 10
  puts "Running tests against Docker services"
  sh "APP_URL=http://localhost:5000 rspec spec"
  puts "Stopping Docker services"
  sh "docker-compose down"
end

desc 'Initialize the database'
task :init_db do
  puts "Initializing the database"
  sh "curl -s http://localhost:5000/init_db"
end
