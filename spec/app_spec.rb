require 'spec_helper'
require 'rspec'
require 'rack/test'
require 'httparty'
require 'json'

# These RSpec tests validate that the API endpoints of the Detector Gadget app
# are functioning correctly. They test authentication, job submission, and
# retrieval of results.

RSpec.describe "Detector Gadget App" do
  include Rack::Test::Methods

  # Configuration
  let(:base_url) { ENV['APP_URL'] || 'http://localhost:5000' }
  let(:username) { 'test_user' }
  let(:password) { 'test_password' }
  let(:test_file) { File.join(File.dirname(__FILE__), 'fixtures', 'sample.txt') }
  let(:session) { HTTParty::CookieJar.new }

  # Helper methods
  def get_auth_cookies(username, password)
    response = HTTParty.post(
      "#{base_url}/login",
      body: { username: username, password: password },
      follow_redirects: false
    )
    
    response.get_fields('Set-Cookie').each do |cookie|
      session.add_cookies(cookie)
    end
    
    session
  end

  def request_with_session(method, path, options = {})
    options[:headers] ||= {}
    options[:headers]['Cookie'] = session.cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
    
    HTTParty.send(method, "#{base_url}#{path}", options)
  end

  # Test Cases
  
  # Authentication Tests
  describe "Authentication" do
    it "should allow user registration" do
      response = HTTParty.post(
        "#{base_url}/register",
        body: {
          username: "#{username}_#{Time.now.to_i}",
          password: password,
          confirm_password: password
        },
        follow_redirects: false
      )
      
      expect(response.code).to be_between(200, 302)
    end
    
    it "should allow user login" do
      response = HTTParty.post(
        "#{base_url}/login",
        body: { username: username, password: password },
        follow_redirects: false
      )
      
      expect(response.code).to be_between(200, 302)
      expect(response.headers.include?('Set-Cookie')).to be true
    end
    
    it "should redirect to login page for unauthenticated users" do
      response = HTTParty.get("#{base_url}/dashboard", follow_redirects: false)
      expect(response.code).to eq(302)
    end
  end
  
  # Dashboard Tests
  describe "Dashboard" do
    before do
      get_auth_cookies(username, password)
    end
    
    it "should display the dashboard page for authenticated users" do
      response = request_with_session(:get, "/dashboard")
      expect(response.code).to eq(200)
      expect(response.body).to include('Your Analysis Jobs')
    end
    
    it "should display charts on the dashboard" do
      response = request_with_session(:get, "/dashboard")
      expect(response.body).to include('statusChart')
      expect(response.body).to include('activityChart')
    end
  end
  
  # Job Submission Tests
  describe "Job Submission" do
    before do
      get_auth_cookies(username, password)
    end
    
    it "should display the submit job form" do
      response = request_with_session(:get, "/submit_job")
      expect(response.code).to eq(200)
      expect(response.body).to include('Submit New Analysis Job')
    end
    
    it "should accept file uploads", :skip => !File.exist?(test_file) do
      file = File.open(test_file)
      
      response = request_with_session(
        :post,
        "/submit_job",
        multipart: true,
        body: {
          file: file,
          output_dest: 'test@example.com'
        }
      )
      
      file.close
      
      expect(response.code).to be_between(200, 302)
    end
    
    it "should accept URL submissions" do
      response = request_with_session(
        :post,
        "/submit_job",
        body: {
          url: 'https://example.com/sample.txt',
          output_dest: 'test@example.com'
        }
      )
      
      expect(response.code).to be_between(200, 302)
    end
  end
  
  # API Tests
  describe "API Endpoints" do
    before do
      get_auth_cookies(username, password)
    end
    
    it "should return job statistics in JSON format" do
      # First, get a job ID from the dashboard
      dashboard_response = request_with_session(:get, "/dashboard")
      
      # Simple regex to extract job ID from the dashboard HTML
      job_id_match = dashboard_response.body.match(/\/job\/(\d+)/)
      
      # Skip test if no jobs exist
      if job_id_match && job_id_match[1]
        job_id = job_id_match[1]
        
        response = request_with_session(:get, "/api/job_stats/#{job_id}")
        expect(response.code).to eq(200)
        
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('id')
        expect(json_response).to have_key('status')
      else
        skip "No jobs found to test API endpoint"
      end
    end
  end
end
