# config.ru
#
# Main Rack configuration file for the Onetime Secret application.
# This file orchestrates the entire application stack, sets up middleware,
# and defines the application's runtime environment.
#
# Usage:
# ```bash
#   $ thin -e dev -R config.ru -p 3000 start
#   $ puma -e development -p 3000 config.ru
#   $ puma -C puma.rb
# ```
#
# Application Structure:
# ```
#   /
#   ├── apps/
#   │   ├── api/
#   │   │   ├── v1/
#   │   │   │   ├── config.ru       # V1 API registration
#   │   │   │   └── application.rb
#   │   │   └── v2/
#   │   │       ├── config.ru       # V2 API registration
#   │   │       └── application.rb
#   │   │
#   │   └── web/
#   │       ├── core/
#   │       │   ├── config.ru       # Core web app registration
#   │       │   └── application.rb
#   │       ├── config.ru           # Web app registration
#   │       └── application.rb
#   │
#   ├── lib/
#   │   ├── app_registry.rb         # Application registry implementation
#   │   └── onetime.rb              # Core Onetime Secret library
#   │
#   └── config.ru                   # Main Rack configuration
# ```
#

# Environment Configuration
# -------------------------------
# Set default environment variables and establish directory structure constants.
# These fundamentals ensure the application knows where to find its resources.
ENV['RACK_ENV'] ||= 'production'
ENV['ONETIME_HOME'] ||= File.expand_path(__dir__).freeze
project_root = ENV['ONETIME_HOME']
app_root = File.join(project_root, '/apps').freeze

# Public Directory Configuration
# Define the location for static web assets
unless defined?(PUBLIC_DIR)
  PUBLIC_DIR = File.join(project_root, '/public/web').freeze
end

# Load Path Configuration
# Add the lib directory to Ruby's load path for require statements
$LOAD_PATH.unshift(File.join(project_root, 'lib'))

# Load application-specific components
require_relative 'apps/app_registry'    # Application registry for mounting apps

# Bootstrap the Application
# -------------------------------
# Applications must be loaded before boot to ensure all Familia models
# are properly registered. This sequence is critical for establishing
# database connections for all model classes.
Onetime.boot! :app

# Application Initialization
# -------------------------------
# Discover and map application modules to their routes
AppRegistry.initialize_applications

# Application Mounting
# Map all registered applications to their respective URI paths
run Rack::URLMap.new(AppRegistry.build)
