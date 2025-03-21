require_relative '../../app_registry'
require_relative 'application'

# Environment Variables
ENV['RACK_ENV'] ||= 'production'
ENV['APP_ROOT'] = File.expand_path(__dir__).freeze
app_root = ENV['APP_ROOT']

# Directory Constants
unless defined?(PUBLIC_DIR)
  PUBLIC_DIR = File.join(app_root, '/public/web').freeze
  APP_DIR = File.join(app_root, '/lib/onetime/app').freeze
end

# Load Paths
$LOAD_PATH.unshift(File.join(app_root, 'lib'))

# Create the app instance
v1_app = API::V1::Application.new

# This line is missing - actually run the application
run v1_app
