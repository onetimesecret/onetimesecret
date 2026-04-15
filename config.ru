# config.ru
#
# frozen_string_literal: true

#
# Usage:
#
#   $ bundle exec puma -C etc/examples/puma.example.rb
#   $ RACK_ENV=development bundle exec puma -C etc/examples/puma.example.rb
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
ENV['RACK_ENV']     ||= 'production'
ENV['ONETIME_HOME'] ||= File.expand_path(__dir__).freeze

# Add lib to load path first
$LOAD_PATH.unshift(File.join(__dir__, 'lib')) unless $LOAD_PATH.include?(File.join(__dir__, 'lib'))

# Early validation: catch missing env vars before the full boot sequence,
# which would otherwise fail deep in config loading with a less obvious error.
if ENV['SECRET'].to_s.strip.empty?
  warn "FATAL: SECRET is not set. Run 'source .env.sh' before starting the app."
  exit 1
end

begin
  require 'onetime'

  # Set execution mode for Puma/Rack web server before boot.
  # This enables initializers (e.g., SetupDiagnostics) to configure
  # process-specific settings like Sentry tags.
  OT.execution_mode = :backend

  # Bootstrap the Application
  # NOTE: Proper semantic logging comes online during boot. Any logging
  # prior to this needs to be output directly via STDOUT/STDERR.
  Onetime.boot! :app

  # Application models need to be loaded before booting
  Onetime::Application::Registry.prepare_application_registry

  Onetime.app_logger.debug "Onetime application booted in #{OT.env} mode. Is ready? #{Onetime.ready?} "

  # Check if application is ready before starting server
  unless Onetime.ready?
    warn 'Application is not ready - goodnight irene'
    $stderr.flush
    exit 87
  end
rescue Interrupt
  # Clean exit on SIGINT during boot — no backtrace needed.
  # This prevents Puma from printing "Unable to load application" with a
  # stack trace when the process manager sends SIGINT (e.g., another
  # service failed to start).
  exit 130 # Standard exit code for SIGINT (128 + signal number 2)
end

# Mount and run Rack applications
run Onetime::Application::Registry.generate_rack_url_map
