require 'rspec'
require 'httparty'
require 'json'

# Ensures that fixture directory exists
def ensure_fixture_dir
  fixture_dir = File.join(File.dirname(__FILE__), 'fixtures')
  Dir.mkdir(fixture_dir) unless Dir.exist?(fixture_dir)
  fixture_dir
end

# Creates a sample test file if it doesn't exist
def create_sample_file
  fixture_dir = ensure_fixture_dir
  sample_file = File.join(fixture_dir, 'sample.txt')
  
  unless File.exist?(sample_file)
    File.open(sample_file, 'w') do |f|
      f.puts "This is a sample file for testing."
      f.puts "It contains some email addresses like test@example.com and admin@example.org."
      f.puts "It also has phone numbers like 555-123-4567 and 123.456.7890."
      f.puts "Credit card number: 4111-1111-1111-1111"
      f.puts "Another card: 5555555555554444"
      f.puts "Some URLs: https://example.com and http://test.org"
    end
  end
  
  sample_file
end

RSpec.configure do |config|
  config.before(:suite) do
    # Create sample test file
    create_sample_file
    
    # Check if the application is running
    begin
      base_url = ENV['APP_URL'] || 'http://localhost:5000'
      response = HTTParty.get(base_url)
      puts "✓ Application is running at #{base_url}"
    rescue Errno::ECONNREFUSED
      puts "✗ Application is not running at #{base_url}. Please start the application before running tests."
    end
  end
  
  # Use expect syntax
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  
  # Mock framework config
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  
  # Run tests in random order
  config.order = :random
end
