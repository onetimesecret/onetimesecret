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
# NOTE: Proper semantic logging comes online during boot. Any logging
# prior to this needs to be output directly via STDOUT/STDERR.
Onetime.boot! :app

Onetime.app_logger.debug "Onetime application booted in #{OT.env} mode. Is ready? #{Onetime.ready?} "

# Check if application is ready before starting server
unless Onetime.ready?
  $stderr.puts 'Application is not ready - goodnight irene'
  $stderr.flush
  exit 87
end

# Mount and run Rack applications
run Onetime::Application::Registry.generate_rack_url_map
