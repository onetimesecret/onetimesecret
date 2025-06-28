# lib/onetime/constants.rb

Warning[:deprecated] = %w[development dev test].include?(ENV['RACK_ENV'].to_s)

require 'bundler/setup'

require 'erb'
require 'securerandom'
require 'syslog'
require 'truemail'

require 'encryptor'
require 'bcrypt'

require 'rack'
require 'otto'
require 'gibbler/mixins'
require 'familia'
require 'storable'

require_relative 'core_ext'
require_relative 'utils'

# Character Encoding Configuration
# Set UTF-8 as the default external encoding to ensure consistent text handling:
# - Standardizes file and network I/O operations
# - Normalizes STDIN/STDOUT/STDERR encoding
# - Provides default encoding for strings from external sources
# This prevents encoding-related bugs, especially on fresh OS installations
# where locale settings may not be properly configured.
Encoding.default_external = Encoding::UTF_8

# Onetime is the core of the Onetime Secret application.
# It contains the core classes and modules that make up
# the app. It is the main namespace for the application.
#
module Onetime
  unless defined?(Onetime::HOME)
    HOME = File.expand_path('../..', __dir__)

    # Ensure immediate flushing of stdout to improve real-time logging visibility.
    # This is particularly useful in development and production environments where
    # timely log output is crucial for monitoring and debugging purposes.
    #
    # Enabling sync can have a performance impact in high-throughput environments.
    #
    # NOTE: Use STDOUT the immuntable constant here, not $stdout (global var).
    STDOUT.sync = Onetime::Utils.yes?(ENV.fetch('STDOUT_SYNC', false))
  end
end

# Sets the SIGINT handler for a graceful shutdown and prevents Sentry from
# trying to send events over the network when we're shutting down via ctrl-c.
trap('SIGINT') do
  OT.li 'Shutting down gracefully...'

  if OT.conf[:d9s_enabled]
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
