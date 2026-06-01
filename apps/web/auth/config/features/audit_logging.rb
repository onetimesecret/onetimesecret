# apps/web/auth/config/features/audit_logging.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  module AuditLogging
    def self.configure(auth)
      auth.enable :audit_logging

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

      # ========================================================================
      # Orphaned-session guard for logout
      # ========================================================================
      #
      # On logout, skip the audit INSERT when the account has been deleted.
      # This prevents a noisy Sequel ERROR log from the FK violation. The
      # around_rodauth rescue in error_handling.rb remains the safety net
      # for non-logout routes where the FK trip-wire detects orphaned sessions.
      #
      # rubocop:disable Lint/NestedMethodDefinition
      auth.auth_class_eval do
        alias_method :_original_add_audit_log, :add_audit_log

        def add_audit_log(account_id, action)
          if action == :logout && account_id && db[:accounts].where(id: account_id).empty?
            Auth::Logging.log_auth_event(
              :audit_log_skipped_orphaned_account,
              level: :warn,
              account_id: account_id,
              action: action,
              message: 'Skipped audit log INSERT for deleted account on logout',
            )
            return
          end

          _original_add_audit_log(account_id, action)
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition
    end
  end
end
