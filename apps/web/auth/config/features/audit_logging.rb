# apps/web/auth/config/features/audit_logging.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  module AuditLogging
    def self.configure(auth)
      # ========================================================================
      # Table Configuration
      # ========================================================================
      auth.audit_logging_table :account_authentication_audit_logs
      auth.audit_logging_account_id_column :account_id
      auth.audit_logging_message_column :message
      auth.audit_logging_metadata_column :metadata

      # ========================================================================
      # Default Metadata
      # ========================================================================
      #
      # Provides a base metadata structure for all audit log entries.
      # Action-specific metadata will be merged with this default.
      #
      auth.audit_log_metadata_default do
        {
          timestamp: Time.now.utc.iso8601,
          environment: ENV['RACK_ENV'] || 'development',
        }
      end
    end
  end
end
