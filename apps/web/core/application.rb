# apps/web/core/application.rb

require 'rack'
require 'otto'
require 'json'

require_relative 'controllers'
# require_relative 'models'
# require_relative 'logic'

module Core
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
      routes_path = File.join(ENV['APP_ROOT'], 'apps/web/core/routes')

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
          Onetime.li "Core web app warmup completed"
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

  end
end


# Register with AppRegistry during load
AppRegistry.register('/', Core::Application)
