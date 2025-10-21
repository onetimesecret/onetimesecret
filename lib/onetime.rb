# lib/onetime.rb

require 'bundler/setup'
require 'securerandom'

require 'truemail'

require 'erb'

require 'encryptor'
require 'bcrypt'

begin
  require 'sendgrid-ruby'
rescue LoadError
  warn "SendGrid is not installed. Mailer not available."
end

require 'rack'
require 'otto'
require 'familia'

Warning[:deprecated] = %w[development dev test testing].include?(ENV['RACK_ENV'].to_s.downcase)

# Ensure immediate flushing of stdout to improve real-time logging visibility.
# This is particularly useful in development and production environments where
# timely log output is crucial for monitoring and debugging purposes.
#
# Enabling sync can have a performance impact in high-throughput environments.
#
# NOTE: Use STDOUT the immuntable constant here, not $stdout (global var).
#
STDOUT.sync = ENV.fetch('STDOUT_SYNC', nil) && %w[true yes 1].include?(ENV.fetch('STDOUT_SYNC', nil))

# Onetime is the core of the Onetime Secret application.
# It contains the core classes and modules that make up
# the app. It is the main namespace for the application.
#
module Onetime
  unless defined?(Onetime::HOME)
    HOME = File.expand_path(File.join(File.dirname(__FILE__), '..'))
  end

  # Add apps directories to load path for requires like 'v1/refinements'
  unless defined?(Onetime::APPS_ROOT)
    APPS_ROOT = File.join(HOME, 'apps').freeze
    $LOAD_PATH.unshift(File.join(APPS_ROOT, 'api'))
    $LOAD_PATH.unshift(File.join(APPS_ROOT, 'web'))
  end

  require_relative 'onetime/class_methods'
  extend ClassMethods

  # Load application framework components
  require_relative 'onetime/application'

  # Extend Rack::Request with Otto and Onetime-specific methods
  require_relative 'onetime/initializers/extend_rack_request'
end

# Sets the SIGINT handler for a graceful shutdown and prevents Sentry from
# trying to send events over the network when we're shutting down via ctrl-c.
trap('SIGINT') do
  OT.li 'Shutting down gracefully...'
  OT.with_diagnostics do
    begin
      Sentry.close  # Attempt graceful shutdown with a short timeout
    rescue ThreadError => ex
      OT.ld "Sentry shutdown interrupted: #{ex} (#{ex.class})"
    rescue StandardError => ex
      # Ignore Sentry errors during shutdown
      OT.le "Error during shutdown: #{ex} (#{ex.class})"
      OT.ld ex.backtrace.join("\n")
    end
  end
  exit
end

require_relative 'onetime/alias'
require_relative 'onetime/errors'
require_relative 'onetime/error_handler'
require_relative 'onetime/utils'
require_relative 'onetime/version'
require_relative 'onetime/config'
require_relative 'onetime/auth_config'
require_relative 'onetime/models'
require_relative 'onetime/cluster'
require_relative 'onetime/boot'
