# lib/onetime/initializers/setup_auth_database.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # Handles fork safety for the Auth database (Sequel/PostgreSQL).
    #
    # SSL connections established in the master process before fork will have
    # corrupted state in workers (the SSL session is process-local). This
    # manifests as "SSL error: decryption failed or bad record mac" errors.
    #
    # The Auth::Database uses a LazyConnection proxy that reconnects on first
    # use, so we just need to disconnect before fork. Each worker will
    # establish its own connection when it first accesses the database.
    #
    class SetupAuthDatabase < Onetime::Boot::Initializer
      @depends_on = [:logging]
      @provides   = [:auth_database]
      @phase      = :fork_sensitive

      def execute(_context)
        # No-op during normal boot. The Auth::Database connection is lazy
        # and will establish itself when first accessed. This initializer
        # exists solely to participate in fork cleanup.
        return unless Onetime.auth_config&.full_enabled?

        OT.ld '[init] Auth database fork handler registered'
      end

      # Disconnect Sequel before fork to prevent SSL state corruption.
      # Called by InitializerRegistry.cleanup_before_fork from Puma's before_fork hook.
      def cleanup
        return unless defined?(Auth::Database)

        # Check if connection was ever established
        return unless Auth::Database.connected?

        OT.ld '[SetupAuthDatabase] Disconnecting auth database before fork'
        Auth::Database.reset_connection!
      rescue StandardError => ex
        warn "[SetupAuthDatabase] Error during cleanup: #{ex.message}"
      end

      # Reconnection is handled automatically by LazyConnection on first use.
      # This method exists for consistency with the fork-sensitive interface.
      def reconnect
        # LazyConnection re-establishes on first query, nothing to do here.
        # Logging is intentionally omitted to avoid noise in worker boot.
      end
    end
  end
end
