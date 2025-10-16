# try/test_helpers.rb

ENV['RACK_ENV'] ||= 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..', '..')).freeze

project_root = ENV['ONETIME_HOME']
app_root = File.join(project_root, '/apps').freeze

$LOAD_PATH.unshift(File.join(app_root))

require 'onetime'
require 'onetime/models'

OT::Config.path = File.join(project_root, 'spec', 'config.test.yaml')

# When DEBUG_DATABASE=1, the database commands are logged to stderr
Onetime.setup_database_logging

def generate_random_email
  # Generate a random username
  username = (0...8).map { ('a'..'z').to_a[rand(26)] }.join
  # Define a domain
  domain = "onetimesecret.com"
  # Combine to form an email address
  "#{username}@#{domain}"
end

# Mock StrategyResult for testing Logic classes
# Logic::Base now expects a StrategyResult object instead of separate session/customer
class MockStrategyResult
  attr_reader :session, :user

  def initialize(session = nil, user = nil)
    @session = session || {}
    @user = user
  end

  def authenticated?
    @session['authenticated'] == true || @user != nil
  end
end

# Legacy MockSession for backward compatibility
# Use MockStrategyResult for new Logic tests
class MockSession
  def authenticated?
    true
  end

  def short_identifier
    "mock_short_identifier"
  end

  def ipaddress
    "mock_ipaddress"
  end

  def add_shrimp
    "mock_shrimp"
  end

  def get_error_messages
    []
  end

  def get_info_messages
    []
  end

  def get_form_fields!
    {}
  end

  def [](key)
    nil
  end

  def []=(key, value)
    value
  end
end
