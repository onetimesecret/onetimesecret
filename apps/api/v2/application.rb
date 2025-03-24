# apps/api/v2/application.rb

require 'rack'
require 'otto'
require 'json'

require_relative 'models'
require_relative 'logic'
require_relative 'controllers'

module V2
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
      routes_path = File.join(ENV['ONETIME_HOME'], 'apps/api/v2/routes')

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

          # Log warmup completion
          Onetime.li "V2 warmup completed"
        end

        # Common middleware stack
        use Rack::ClearSessionMessages
        use Rack::DetectHost

        # Applications middleware stack
        use Onetime::DomainStrategy

        # Application router
        run router_instance
      end.to_app
    end

    # Registering with AppRegistry during load makes this application
    # available to the main config.ru file.
    AppRegistry.register('/api/v2', self) # i.e. V2::Application
  end
end
