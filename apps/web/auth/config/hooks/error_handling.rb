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
          # Extract account_id from session if available
          session_account_id = begin
                                 session[:account_id]
          rescue StandardError
                                 'unknown'
          end

          # Check if this is an orphaned session (account deleted while session active)
          # This can happen when an admin deletes an account while the user has an active session
          account_exists = begin
            session_account_id.is_a?(Integer) && !db[:accounts].where(id: session_account_id).empty?
          rescue StandardError
            false
          end

          if account_exists
            # Account exists but FK failed - this is the dev environment issue
            # (e.g., worktree with shared Redis but separate SQLite DBs)
            diagnostic_hint = <<~HINT.strip
              Account ID #{session_account_id} exists in Redis session but FK constraint
              still failed. This typically occurs in worktree/multi-instance dev setups
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
            raise ex
          end

          # Orphaned session detected - handle gracefully
          Auth::Logging.log_auth_event(
            :orphaned_session_detected,
            level: :warn,
            current_route: current_route,
            request_path: request.path,
            session_id: session.id,
            orphaned_account_id: session_account_id,
            message: 'Session references deleted account - clearing session',
          )

          # Clear the orphaned session
          begin
            session.destroy
          rescue StandardError => destroy_error
            Auth::Logging.log_auth_event(
              :session_destroy_failed,
              level: :error,
              error: destroy_error.message,
            )
          end

          # Return appropriate response based on route
          # For logout: success (they wanted to log out anyway)
          # For other routes: 401 unauthorized
          if current_route == :logout
            request.halt([200, { 'Content-Type' => 'application/json' },
                          [JSON.generate({ success: true, message: 'Logged out' })]])
          else
            request.halt([401, { 'Content-Type' => 'application/json' },
                          [JSON.generate({ error: 'Session expired', success: false })]])
          end
        rescue StandardError => ex
          Auth::Logging.log_auth_event(
            :unhandled_exception,
            level: :error,
            current_route: current_route,
            request_path: request.path,
            session_id: session.id,
            error_class: ex.class.name,
            error_message: ex.message,
            error_backtrace: ex.backtrace&.first(5),
          )
          raise ex
        end
      end
    end
  end
end
