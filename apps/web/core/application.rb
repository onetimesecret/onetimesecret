# apps/web/core/application.rb

require_relative '../../app_base'

require_relative 'controllers'

module Core
  class Application < ::BaseApplication
    @prefix = '/'

    private

    def build_router
      is_enabled = OT.conf.dig(:site, :interface, :ui, :enabled) || false

      enabled_routes_path = File.join(ENV['ONETIME_HOME'], 'apps/web/core/routes')
      disabled_routes_path = File.join(ENV['ONETIME_HOME'], 'apps/web/core/routes.disabled')

      routes_path = is_enabled ? enabled_routes_path : disabled_routes_path

      router = Otto.new(routes_path)

      # Default error responses
      headers = { 'Content-Type' => 'text/html' }
      router.not_found = [404, headers, ['Not Found']]
      router.server_error = [500, headers, ['Internal Server Error']]

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
          Onetime.li "Core warmup completed"
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
