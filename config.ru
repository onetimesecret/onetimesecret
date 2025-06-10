# config.ru
#
# Main Rack configuration file for the Onetime Secret project.
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
# Project Structure:
# ```
#   /
#   ├── apps/
#   │   ├── app_registry.rb
#   │   ├── api/
#   │   │   ├── v1/
#   │   │   │   └── application.rb
#   │   │   └── v2/
#   │   │       └── application.rb
#   │   └── web/
#   │       └── core/
#   │           └── application.rb
#   │
#   ├── lib/
#   │   └── onetime.rb
#   │
#   └── config.ru
# ```
#

# Establish the environment
ENV['RACK_ENV'] ||= 'production'
ENV['ONETIME_HOME'] ||= File.expand_path(__dir__).freeze

require_relative 'apps/app_registry'

# Application models need to be loaded before booting
AppRegistry.prepare_application_registry

# Bootstrap the application
Onetime.safe_boot! :app

# Application Mounting
run AppRegistry.create_rack_application_map
