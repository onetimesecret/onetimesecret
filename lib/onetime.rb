# lib/onetime.rb
#
# frozen_string_literal: true

require 'bundler/setup'

if ENV['BOOT_TICKER_TAPE']
  require_relative 'onetime/boot/ticker_tape'
  $ticker = Onetime::Boot::TickerTape.new.tap(&:start)
end

require 'securerandom'

require 'truemail'

require 'erb'

require 'encryptor'
require 'bcrypt'

begin
  require 'sendgrid-ruby'
rescue LoadError
  warn 'SendGrid is not installed. Mailer not available.'
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

# Onetime is the core of the Onetime Secret application.
# It contains the core classes and modules that make up
# the app. It is the main namespace for the application.
#
module Onetime
  require_relative 'onetime/utils'
  if Onetime::Utils.yes?(ENV.fetch('STDOUT_SYNC', false))
    $stdout.sync = true
    $stderr.sync = true
    if Onetime::Utils.yes?(ENV['ONETIME_DEBUG'])
      $stderr.puts <<~NOTICE # rubocop:disable Style/StderrPuts
        [onetime] STDOUT and STDERR sync mode enabled. Output will be unbuffered
        which is useful for real-time logging visibility but is not recommended
        for production. It makes the process IO bound which can impact performance.
      NOTICE
    end
  end

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

  # Load runtime state management
  require_relative 'onetime/runtime'

  # Load application framework components
  require_relative 'onetime/application'

  # Load backwards compatibility accessors
  # TODO: Remove this require and delete lib/onetime/deprecated_methods.rb
  # after migrating all code to use Runtime state objects directly
  require_relative 'onetime/deprecated_methods'
end

# Sets the SIGINT handler for a graceful shutdown and prevents Sentry from
# trying to send events over the network when we're shutting down via ctrl-c.
trap('SIGINT') do
  # Prevent re-entry if signal is received again during cleanup
  trap('SIGINT', 'DEFAULT')

  # Cannot use semantic_logger from trap context - use direct STDERR
  warn 'Shutting down gracefully...'
  OT.with_diagnostics do
      Sentry.close  # Attempt graceful shutdown with a short timeout
    rescue ThreadError => ex
      warn "Sentry shutdown interrupted: #{ex} (#{ex.class})"
    rescue Sentry::Error, IOError, SystemCallError => ex
      # Ignore Sentry-related/network errors during shutdown
      warn "Error during shutdown: #{ex} (#{ex.class})"
      warn(ex.backtrace&.join("\n")) if OT.debug?
  end

  # Re-raise signal to trigger default handler (ensures proper exit code 130)
  Process.kill('SIGINT', Process.pid)
end

require_relative 'onetime/alias'
require_relative 'onetime/errors'
require_relative 'onetime/error_handler'
require_relative 'onetime/version'
require_relative 'onetime/config'
require_relative 'onetime/auth_config'
require_relative 'onetime/billing_config'
require_relative 'onetime/models'
require_relative 'onetime/cluster'
require_relative 'onetime/boot'
