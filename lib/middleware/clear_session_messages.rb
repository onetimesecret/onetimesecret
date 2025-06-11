require 'logger'

module Rack
  # ClearSessionMessages: Clears session messages after a successful response.
  #
  # This middleware operates on the response, not affecting requests or errors.
  class ClearSessionMessages
    attr_reader :logger

    def initialize(app, io: $stderr)
      @app = app
      @logger = ::Logger.new(io, level: :info)
    end

    # Entry point for the middleware. Processes the request and clears session
    # messages if conditions are met.
    def call(env)
      # Pass the request down the middleware stack
      status, headers, response = @app.call(env)

      # Retrieve the session object after the application has processed
      # the request. NOTE: This will be nil for API requests.
      sess = env['rack.session']

      # Ensure the session is properly configured before proceeding
      return [status, headers, response] unless check_session_messages(sess)

      # Determine if we should clear the session messages
      response_has_content = !Rack::Utils::STATUS_WITH_NO_ENTITY_BODY.include?(status)
      is_successful_response = status < 300

      if response_has_content && is_successful_response
        # Clear the messages if all conditions are met
        sess.clear_messages!
        logger.info('[ClearSessionMessages] Session messages cleared')
      end

      [status, headers, response]
    end

    protected

    # Verify that the session object is properly configured and that
    # there are messages to clear.
    def check_session_messages(sess)
      unless sess
        logger.debug('[ClearSessionMessages] Session object not found in environment')
        return false
      end

      unless sess.respond_to?(:messages)
        logger.warn("[ClearSessionMessages] Session object lacks 'messages' method")
        return false
      end

      unless sess.messages.respond_to?(:clear)
        logger.warn("[ClearSessionMessages] Session messages object lacks 'clear' method")
        return false
      end

      sess.messages.exists?
    end
  end
end
