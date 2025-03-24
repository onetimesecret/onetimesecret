# apps/api/v1/application.rb

require 'rack'
require 'otto'
require 'json'

require_relative 'models'
require_relative 'logic'
require_relative 'controllers'

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
      routes_path = File.join(ENV['ONETIME_HOME'], 'apps/api/v1/routes')

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
          require_relative 'logic'
          require_relative 'models'

          V1::RateLimit.register_events OT.conf[:limits]
          OT.li "rate limits: #{V1::RateLimit.events.map { |k,v| "#{k}=#{v}" }.join(', ')}"

          # Log warmup completion
          Onetime.li "V1 warmup completed"
        end

        # Common middleware stack
        use Rack::HandleInvalidUTF8
        use Rack::HandleInvalidPercentEncoding
        use Rack::ClearSessionMessages
        use Rack::DetectHost

        # Applications middleware stack
        use Onetime::DomainStrategy

        # Application router
        run router_instance
      end.to_app
    end

  end
end

# Register with AppRegistry during load
AppRegistry.register('/api/v1', V1::Application)
