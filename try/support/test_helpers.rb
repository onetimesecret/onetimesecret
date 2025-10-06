# try/test_helpers.rb

ENV['RACK_ENV'] ||= 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..', '..')).freeze

project_root = ENV['ONETIME_HOME']
app_root = File.join(project_root, '/apps').freeze

$LOAD_PATH.unshift(File.join(app_root, 'api'))
$LOAD_PATH.unshift(File.join(app_root, 'web'))

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
