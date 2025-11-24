# apps/web/auth/config/hooks/error_handling.rb
#
# frozen_string_literal: true

#
# The around_rodauth handler is called for every route, which we use as
# a global error handler.
#

module Auth::Config::Hooks
  module ErrorHandling
    def self.configure(auth)
      auth.around_rodauth do |&blk|
        if Onetime.debug?
          Auth::Logging.log_auth_event(
            :around_rodauth,
            level: :debug,
            session_id: session.id,
            current_route: current_route,
            request_path: request.path,
          )
        end
        begin
          super(&blk)
        rescue Sequel::ForeignKeyConstraintViolation => ex
          # Check if this is the audit logging account_id mismatch
          if ex.message.include?('account_authentication_audit_logs') &&
             ex.message.include?('account_id')

            # Extract account_id from session if available
            session_account_id = session[:account_id] rescue 'unknown'

            diagnostic_hint = <<~HINT.strip
              Account ID #{session_account_id} exists in Redis session but not in SQLite
              auth database. This typically occurs in worktree/multi-instance dev setups
              with shared Redis. Consider: (1) seeding accounts table, (2) using isolated
              Redis, or (3) clearing Redis session data.
            HINT

            Auth::Logging.log_auth_event(
              :auth_database_consistency_error,
              level: :error,
              current_route: current_route,
              request_path: request.path,
              session_id: session.id,
              error_class: ex.class.name,
              error_message: ex.message,
              diagnostic_hint: diagnostic_hint,
              backtrace: ex.backtrace&.first(5),
            )
          end
          raise ex
        rescue StandardError => ex
          Auth::Logging.log_auth_event(
            :unhandled_exception,
            level: :error,
            current_route: current_route,
            request_path: request.path,
            session_id: session.id,
            error_class: ex.class.name,
            error_message: ex.message,
            backtrace2: ex.backtrace&.first(5), # semantic logger removes `backtrace`?
          )
          raise ex
        end
      end
    end
  end
end
