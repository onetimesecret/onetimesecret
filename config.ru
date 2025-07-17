# config.ru
#
# Rack entry point for Onetime Secret.
#
# This file serves as the main configuration and bootstrap point for the entire
# application. It initializes the runtime environment, loads necessary components,
# and creates the Rack application map that routes requests to the appropriate
# sub-applications (web interface and API endpoints).
#
# Usage Examples:
# ```bash
#   # Development with Thin
#   $ thin -e development -R config.ru -p 3000 start
#
#   # Development with Puma (direct)
#   $ puma -e development -p 3000 config.ru
#
#   # Production with Puma (using config file)
#   $ puma -C puma.rb
# ```
#
# Project Structure:
# ```
#   /
#   ├── apps/
#   │   ├── api/
#   │   │   ├── v1/application.rb
#   │   │   └── v2/application.rb
#   │   │
#   │   ├── web/
#   │   │   └── frontend/application.rb
#   │   │
#   │   ├── app_registry.rb
#   │   ├── base_application.rb
#   │   └── middleware_stack.rb
#   │
#   ├── lib/
#   │   ├── onetime/
#   │   │   ├── boot.rb
#   │   │   └── config.rb
#   │   │
#   │   └── onetime.rb
#   │
#   └── config.ru
# ```
#

# Establish the environment
ENV['RACK_ENV']     ||= 'production'.freeze
ENV['ONETIME_HOME'] ||= File.expand_path(__dir__).freeze

require_relative 'apps/app_registry'

# Application models need to be loaded before booting
AppRegistry.prepare_application_registry

# Bootstrap the configuration and core components
Onetime.safe_boot!

# Mount and run Rack applications
run AppRegistry.generate_rack_url_map
