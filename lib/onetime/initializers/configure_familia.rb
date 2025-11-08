# lib/onetime/initializers/configure_familia.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # Configures Familia's URI early in the boot process.
    #
    # This must run before detect_legacy_data_and_warn because that
    # method uses Familia.with_isolated_dbclient which needs Familia.uri
    # to be set to the correct value from the configuration.
    #
    # Without this, Familia.uri defaults to redis://127.0.0.1:6379
    # which causes connection failures in Docker environments where
    # Redis/Valkey is on a different host.
    #
    # @return [void]
    #
    def configure_familia
      uri = OT.conf.dig('redis', 'uri')

      # Early validation: Check if Redis URI is properly configured
      if uri.nil? || uri.empty? || uri.include?('CHANGEME')
        OT.boot_logger.info "[init] Configure Familia URI: Invalid URI: #{uri || '<nil>'}"
        raise Onetime::Problem, "Redis URI not configured (#{uri})"
      end

      # Set Familia's URI so it's available for isolated connections
      # during legacy data detection and other pre-connection operations
      Familia.uri = uri

      # Set encryption key with version to allow for future key rotation.
      # Without this config, familia's encrypted fields will raise an error
      # when trying to set or reveal a value.
      secret_key = ENV['SECRET']
      raise "SECRET environment variable not set or empty" if secret_key.to_s.empty?

      Familia.config.encryption_keys = {
        v1: secret_key,
      }
      Familia.config.current_key_version = :v1

      OT.boot_logger.debug "[init] Configure Familia URI: #{uri}"
    end
  end
end
