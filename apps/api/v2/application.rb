# apps/api/v2/application.rb

require_relative '../../app_base'

require_relative 'models'
require_relative 'logic'
require_relative 'controllers'

module V2
  class Application < ::BaseApplication
    @prefix = '/api/v2'

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

  end
end
