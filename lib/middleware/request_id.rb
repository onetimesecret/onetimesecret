# lib/middleware/request_id.rb

module Rack
  # Rack middleware that ensures every HTTP request has a unique identifier.
  #
  # This middleware provides request tracing capabilities by:
  # - Preserving existing X-Request-ID headers from clients
  # - Generating new request IDs when none are provided
  # - Adding the request ID to both the Rack environment and response headers
  #
  # The request ID is accessible throughout the request lifecycle via the
  # Rack environment and is automatically included in HTTP responses for
  # client-side correlation.
  #
  # @example Basic usage with default SecureRandom.hex generator
  #   use Middleware::RequestId
  #
  # @example Custom ID generator (e.g., UUIDv7 with timestamp)
  #   use Middleware::RequestId, generator: -> { SecureRandom.uuid_v7 }
  #
  # @example Project-specific generator (e.g. that uses Familia)
  #   use Middleware::RequestId, generator: -> { Familia.generate_trace_id }
  #
  # @example Method-based generator
  #   class MyApp
  #     def self.generate_request_id
  #       "req_#{Time.now.to_i}_#{SecureRandom.hex(8)}"
  #     end
  #   end
  #
  #   use Middleware::RequestId, generator: MyApp.method(:generate_request_id)
  #
  class RequestId
    # HTTP environment key for the incoming request ID header
    HEADER = 'HTTP_X_REQUEST_ID'

    # HTTP response header name for the request ID, lowercase for Rack 3.x compatibility
    RESPONSE_HEADER = 'x-request-id'

    # Initialize the RequestId middleware.
    #
    # @param app [#call] The Rack application to wrap
    # @param generator [#call, nil] A callable object that generates request IDs.
    #   Defaults to a lambda that calls SecureRandom.hex for backward compatibility.
    #   The callable should return a String that serves as a unique request identifier.
    #
    # @example Initialize with default generator
    #   Middleware::RequestId.new(app)
    #
    # @example Initialize with custom generator
    #   Middleware::RequestId.new(app, generator: -> { MyIDService.generate })
    #
    def initialize(app, generator: nil)
      @app = app
      @generator = generator || -> { SecureRandom.hex }
    end

    # Process the HTTP request through the middleware stack.
    #
    # This method:
    # 1. Checks for an existing X-Request-ID in the request headers
    # 2. Uses the existing ID or generates a new one if missing/empty
    # 3. Stores the ID in the Rack environment for downstream access
    # 4. Processes the request through the application stack
    # 5. Adds the request ID to the response headers
    #
    # @param env [Hash] The Rack environment hash containing request data
    # @return [Array<Integer, Hash, #each>] Standard Rack response tuple of
    #   [status_code, headers_hash, response_body]
    #
    # @example Accessing the request ID in your application
    #   # In a Rack app or middleware
    #   request_id = env['HTTP_X_REQUEST_ID']
    #
    def call(env)
      env[HEADER]              = env.key?(HEADER) ? env[HEADER] : @generator.call
      status, headers, body    = @app.call(env)
      headers[RESPONSE_HEADER] = env[HEADER]
      [status, headers, body]
    end
  end
end
