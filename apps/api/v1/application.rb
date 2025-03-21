# apps/api/v1/application.rb

require 'rack'
require 'otto'
require 'json'

require_relative 'controller'
require_relative 'models'
require_relative 'logic'


module V1
  class Application
    attr_reader :options, :router, :rack_app

    def initialize(options = {})
      @options = options
      @router = build_router
      @rack_app = build_rack_app
    end

    def call(env)
      rack_app.call(env)
    end

    private

    def build_router
      routes_path = File.join(ENV['APP_ROOT'], 'apps/api/v1/routes')

      router = Otto.new(routes_path)

      # Default error responses
      headers = { 'Content-Type' => 'application/json' }
      router.not_found = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end

    def build_rack_app
      # Capture router reference in local variable for block access
      # Rack::Builder uses `instance_eval` internally, creating a new context
      # so inside of it `self` refers to the Rack::Builder instance.
      router_instance = router

      Rack::Builder.new do

        warmup do
          # Expensive initialization tasks
          # Log warmup completion
          Onetime.li "API V1 warmup completed"
        end

        # Core middleware stack
        use Rack::Lint
        use Rack::CommonLogger
        use Rack::ContentLength
        use Rack::HandleInvalidUTF8
        use Rack::HandleInvalidPercentEncoding

        # Application-specific middleware
        use Rack::ClearSessionMessages
        use Rack::DetectHost
        use Onetime::DomainStrategy

        # Conditional middleware
        use Sentry::Rack::CaptureExceptions if defined?(Sentry::Rack::CaptureExceptions)

        # Application router
        run router_instance
      end.to_app
    end

  end
end


# Register with AppRegistry during load
AppRegistry.register('/api/v1', V1::Application)
