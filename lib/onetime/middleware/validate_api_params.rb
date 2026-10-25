# frozen_string_literal: true

require 'json'
require 'rack'
require 'familia/json_serializer'

module Onetime
  module Middleware
    # Runs at the existing multipart boundary, before locale/session consumers
    # and Rack::Parser (whose default parse-error response is an empty 400).
    # Keep the rescue around parsing only: downstream failures are not input errors.
    class ValidateAPIParams
      API_PATH = %r{\A/api/(?:v2|v3|incoming)(?:/|\z)}

      def self.api_request?(env)
        "#{env['SCRIPT_NAME']}#{env['PATH_INFO']}".match?(API_PATH)
      end

      def self.bad_request(env, message)
        body = env['REQUEST_METHOD'] == 'HEAD' ? [] : [JSON.generate(message: message)]
        [400, { 'content-type' => 'application/json', 'cache-control' => 'private, no-store' }, body]
      end

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless self.class.api_request?(env)

        request = Rack::Request.new(env)
        begin
          request.GET
        rescue Rack::BadRequest
          return self.class.bad_request(env, 'Invalid query parameters')
        end

        case request.media_type
        when 'application/json'
          # Validate without changing Rack::Parser's coercion or merge behavior.
          # Rewind even on failure; the existing parser remains the body consumer.
          input = env['rack.input']
          if input
            begin
              Familia::JsonSerializer.parse(input.read)
            rescue Familia::SerializerError
              return self.class.bad_request(env, 'Invalid JSON request body')
            ensure
              input.rewind if input.respond_to?(:rewind)
            end
          end
        when 'application/x-www-form-urlencoded', nil
          # Rack also parses POST bodies without a Content-Type as form data.
          begin
            request.POST
          rescue Rack::BadRequest
            return self.class.bad_request(env, 'Invalid form parameters')
          ensure
            input = env['rack.input']
            input.rewind if input.respond_to?(:rewind)
          end
        end

        @app.call(env)
      end
    end
  end
end
