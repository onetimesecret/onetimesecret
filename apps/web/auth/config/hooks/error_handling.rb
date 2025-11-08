# apps/web/auth/config/hooks/error_handling.rb

#
# The around_rodauth handler is called for every route, which we use as
# a global error handler.
#

module Auth::Config::Hooks
  module ErrorHandling
    def self.configure(auth)
      auth.around_rodauth do |&blk|
        Auth::Logging.log_auth_event(
          :around_rodauth,
          level: :debug,
          session_id: session.id,
          current_route: current_route,
          request_path: request.path,
        ) if Onetime.debug?
        begin
          super(&blk)
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
