
require 'logger'

module Rack

  # Response middleware. Clears session messages after a successful response.
  class ClearSessionMessages

    attr_reader :logger

    def initialize(app, io: $stdout, check_enabled: nil)
      @app = app
      @logger = ::Logger.new(io, level: :info)
    end

    # The call method is the entry point for the middleware.
    # It receives the env object, which is a hash containing all the environment
    # variables and request-specific data.
    def call(env)
      # Call the next middleware or application in the stack.
      # The env object is passed by value, but since it is a reference to a hash,
      # any modifications made to it will be visible to subsequent middleware and the final application.
      status, headers, response = @app.call(env)

      # Access the session object from the env hash.
      # The session object is expected to be stored in env['rack.session'].
      sess = env['rack.session']

      # Clear session messages if all of the following conditions are met:
      # 1. The session object exists
      # 2. The response has a body (is not a redirect or other headerless response)
      # 3. The status code indicates success (less than 300)
      # 4. The session object has a 'messages' method that returns a Redis list object
      response_has_content = !Rack::Utils::STATUS_WITH_NO_ENTITY_BODY.include?(status)

      if sess && response_has_content && status < 300 && sess.respond_to?(:messages)
        # The 'messages' method is expected to return a Redis list object from redis-rb or Familia
        # This list object should have a 'clear' method to remove all items from the list
        sess.messages.clear if sess.messages.respond_to?(:clear)
        logger.info("[ClearSessionMessages] Session messages cleared")
      end

      if sess && response_has_content && status < 300
        unless sess.respond_to?(:messages)
          logger.warn("[ClearSessionMessages] Session object does not respond to 'messages' method")
          return [status, headers, response]
        end

        unless sess.messages.respond_to?(:clear)
          logger.warn("[ClearSessionMessages] Session messages object does not respond to 'clear' method")
          return [status, headers, response]
        end

        # The 'messages' method is expected to return a Redis list object from redis-rb or Familia
        # This list object should have a 'clear' method to remove all items from the list
        sess.messages.clear
      end

      [status, headers, response]
    end
  end
end
