# lib/onetime.rb

require 'bundler/setup'
require 'securerandom'

require 'truemail'

require 'erb'

require 'encryptor'
require 'bcrypt'

require 'sendgrid-ruby'

require 'rack'
require 'otto'
require 'familia'

require_relative 'onetime/core_ext'

# Ensure immediate flushing of stdout to improve real-time logging visibility.
# This is particularly useful in development and production environments where
# timely log output is crucial for monitoring and debugging purposes.
#
# Enabling sync can have a performance impact in high-throughput environments.
#
# NOTE: Use STDOUT the immuntable constant here, not $stdout (global var).
#
STDOUT.sync = ENV['STDOUT_SYNC'] && %w[true yes 1].include?(ENV['STDOUT_SYNC'])

# Onetime is the core of the Onetime Secret application.
# It contains the core classes and modules that make up
# the app. It is the main namespace for the application.
#
module Onetime
  unless defined?(Onetime::HOME)
    HOME = File.expand_path(File.join(File.dirname(__FILE__), '..'))
  end

  require_relative 'onetime/class_methods'
  require_relative 'onetime/boot'
  extend ClassMethods
  extend Initializers
end

# Sets the SIGINT handler for a graceful shutdown and prevents Sentry from
# trying to send events over the network when we're shutting down via ctrl-c.
trap("SIGINT") do
  OT.li "Shutting down gracefully..."
  if OT.d9s_enabled
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

require_relative 'onetime/errors'
require_relative 'onetime/utils'
require_relative 'onetime/version'
require_relative 'onetime/cluster'
require_relative 'onetime/config'
require_relative 'onetime/mail'
require_relative 'onetime/alias'
