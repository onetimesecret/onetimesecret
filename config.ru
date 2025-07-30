# config.ru
#
# Usage:
#
#   $ thin -e dev -R config.ru -p 3000 start
#
# Application Structure:
# ```
# /
# ├── config.ru               # Main Rack configuration
# ├── apps/                   # API (v1, v2, v3) and web applications
# └── lib/                    # Core libraries and app registry
# ```
#


# Establish the environment
ENV['RACK_ENV']     ||= 'production'.freeze
ENV['ONETIME_HOME'] ||= File.expand_path(__dir__).freeze

require_relative 'apps/app_registry'

# Application models need to be loaded before booting
AppRegistry.prepare_application_registry

# Bootstrap the Application
# Applications must be loaded before boot to ensure all Familia models
# are properly registered. This sequence is critical for establishing
# database connections for all model classes.
Onetime.boot! :app

# Mount and run Rack applications
run AppRegistry.generate_rack_url_map
