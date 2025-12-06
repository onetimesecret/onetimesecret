# lib/onetime/initializers/configure_familia.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # ConfigureFamilia initializer
    #
    # Configures Familia's URI early in the boot process. This must run before
    # detect_legacy_data_and_warn because that method uses Familia.with_isolated_dbclient
    # which needs Familia.uri to be set to the correct value from the configuration.
    #
    # Without this, Familia.uri defaults to redis://127.0.0.1:6379 which causes
    # connection failures in Docker environments where Redis/Valkey is on a
    # different host.
    #
    # This initializer configures external library state and doesn't set runtime
    # state that needs to be tracked.
    #
    class ConfigureFamilia < Onetime::Boot::Initializer
      @depends_on = [:logging]
      @provides   = [:familia_config]

      def execute(_context)
        uri = OT.conf.dig('redis', 'uri') || ''

        # Early validation: Check if Redis URI is properly configured
        raise_error = if uri.empty?
          OT.boot_logger.fatal '[configure_familia] Invalid URI'
        elsif uri.include?('CHANGEME')
          OT.boot_logger.warn "[configure_familia] WARNING: Redis password is 'CHANGEME'"
        end

        raise Onetime::Problem, "Redis URI not configured (#{uri})" if raise_error

        # Test environment safety: Ensure tests use port 2121
        if ENV['RACK_ENV'] == 'test' && !uri.include?(':2121')
          raise Onetime::Problem, "Test environment MUST use Redis port 2121, got: #{uri}. Set VALKEY_URL='valkey://127.0.0.1:2121/0'"
        end

        # Set Familia's URI so it's available for isolated connections
        # during legacy data detection and other pre-connection operations
        Familia.uri = uri

        # Set encryption key with version to allow for future key rotation.
        # Without this config, familia's encrypted fields will raise an error
        # when trying to set or reveal a value.
        secret_key = ENV.fetch('SECRET', nil)
        raise 'SECRET environment variable not set or empty' if secret_key.to_s.empty?

        Familia.config.encryption_keys     = {
          v1: secret_key,
        }
        Familia.config.current_key_version = :v1

        OT.boot_logger.debug "[init] Configure Familia URI: #{uri}"
      end
    end
  end
end
