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
          # Handle FK violations that may indicate an orphaned session
          # (account deleted while session active). We detect this by checking
          # if the session's account_id references a non-existent account.
          #
          # For FK violations on other columns (not account-related), or when
          # the account exists, treat as a generic server error.

          # Extract account_id from session if available
          session_account_id = begin
                                 session[:account_id]
          rescue StandardError
                                 nil
          end

          # Determine if this is an orphaned session scenario:
          # - Session has an account_id
          # - That account no longer exists in the database
          is_orphaned_session = false
          if session_account_id.is_a?(Integer)
            account_exists      = begin
              !db[:accounts].where(id: session_account_id).empty?
            rescue StandardError
              # If we can't check, assume account exists (don't mask real errors)
              true
            end
            is_orphaned_session = !account_exists
          end

          # If account exists (or we can't determine), this is a genuine FK error
          unless is_orphaned_session
            Auth::Logging.log_auth_event(
              :foreign_key_constraint_violation,
              level: :error,
              current_route: current_route,
              request_path: request.path,
              session_id: session.id,
              error_class: ex.class.name,
              error_message: ex.message,
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

          # Clear the orphaned session using Rodauth's clear_session for complete cleanup
          begin
            clear_session
          rescue StandardError => destroy_error
            Auth::Logging.log_auth_event(
              :session_destroy_failed,
              level: :error,
              error: destroy_error.message,
            )
          end

          # Return appropriate response based on route
          # For logout: success (they wanted to log out anyway)
          # For other routes: 401 unauthorized with i18n key for frontend translation
          if current_route == :logout
            request.halt([200, { 'Content-Type' => 'application/json' },
                          [JSON.generate({ success: true, message: 'web.auth.logout.success' })]],
                        )
          else
            request.halt([401, { 'Content-Type' => 'application/json' },
                          [JSON.generate({ error: 'web.auth.security.session_expired', success: false })]],
                        )
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
