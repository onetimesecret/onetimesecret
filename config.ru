# config.ru
#
# Usage:
#
#   $ thin -e dev -R config.ru -p 3000 start
#
#   $ puma -e development -p 3000 config.ru
#
# Application Structure:
# ```
# /
# ├── config.ru         # Main Rack configuration
# ├── apps/             # API (v1, v2, v3) and web applications
# └── lib/              # Core libraries, models, and app registry
# ```
#

# Establish the environment
ENV['RACK_ENV']     ||= 'production'.freeze
ENV['ONETIME_HOME'] ||= File.expand_path(__dir__).freeze

# Add lib to load path first
$LOAD_PATH.unshift(File.join(__dir__, 'lib')) unless $LOAD_PATH.include?(File.join(__dir__, 'lib'))

require 'onetime'

# Application models need to be loaded before booting
Onetime::Application::Registry.prepare_application_registry

# Bootstrap the Application
# Applications must be loaded before boot to ensure all Familia models
# are properly registered. This sequence is critical for establishing
# database connections for all model classes.
Onetime.boot! :app

# Mount and run Rack applications
run Onetime::Application::Registry.generate_rack_url_map
