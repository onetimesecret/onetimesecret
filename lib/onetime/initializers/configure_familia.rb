# lib/onetime/initializers/configure_familia.rb

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

      OT.boot_logger.debug "[init] Configure Familia URI: #{uri}"
    end
  end
end
