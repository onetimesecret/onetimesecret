# lib/onetime/middleware/development_environment.rb

require 'rack'

module Onetime
  module Middleware
    # Development environment middleware for Onetime Secret
    #
    # This middleware handles development-specific functionality:
    # 1. Validates Rack compliance using Rack::Lint
    # 2. Sets up a proxy to a local frontend development server when configured
    #
    # It's only activated in development mode and provides a clean separation
    # of development concerns from the main application stack.
    #
    class ViteProxy
      attr_reader :app

      def initialize(app)
        @app = app
        @rack_app = setup_environment
      end

      # Processes the request through the development middleware stack.
      #
      # @param env [Hash] Rack environment hash
      # @return [Array] Standard Rack response array
      def call(env)
        @rack_app.call(env)
      end

      private

      # Configures the middleware stack for development.
      #
      # @return [#call] Configured Rack application
      def setup_environment
        # Keep a reference to the original app instance. We do this outside
        # of the Rack::Builder block which runs in another context.
        app_instance = @app

        Rack::Builder.new do
          # Validate Rack compliance
          use Rack::Lint

          # Get the settings
          config = defined?(OT) ? OT.conf.fetch(:development, {}) : {}

          case config
          in {enabled: true, frontend_host: String => frontend_host}
            if frontend_host.strip.empty?
              OT.ld "[ViteProxy] No frontend host configured to proxy"
            else
              OT.li "[ViteProxy] Using frontend proxy for /dist to #{frontend_host}"
              require 'rack/proxy'

              # Define proxy class for Vite dev server
              proxy_klass = Class.new(Rack::Proxy) do
                define_method(:perform_request) do |env|
                  case env['PATH_INFO']
                  when %r{\A/dist/} then super(env.merge('REQUEST_PATH' => env['PATH_INFO']))
                  else @app.call(env)
                  end
                end
              end

              use proxy_klass, backend: frontend_host
            end
          else
            OT.ld "[ViteProxy] Frontend proxy disabled"
          end

          # Add Rack::Reloader for development
          use Rack::Reloader, 1

          # Pass through to the original app
          run ->(env) { app_instance.call(env) }
        end.to_app

      end
    end
  end
end
