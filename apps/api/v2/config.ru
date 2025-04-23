# apps/api/v2/config.ru
#
# Rackup configuration file for running the API v2 application
# as a standalone service.

require_relative '../../app_registry'
require_relative 'application'

# Environment Variables
ENV['RACK_ENV'] ||= 'production'
ENV['ONETIME_HOME'] = File.expand_path(__dir__).freeze
app_root = ENV['ONETIME_HOME']

# Directory Constants
unless defined?(PUBLIC_DIR)
  PUBLIC_DIR = File.join(app_root, '/public/web').freeze
end

# Load Paths
$LOAD_PATH.unshift(File.join(app_root, 'lib'))

# Create and run the Rack app instance
rack_app = V2::Application.new

run rack_app
