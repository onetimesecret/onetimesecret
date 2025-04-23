# lib/onetime/middleware/vite_proxy.rb
#
# Development proxy middleware for Onetime Secret application.
# Provides development-specific utilities including Vite integration.

require 'rack'

module Onetime
  module Middleware
    # Development environment middleware for Onetime Secret
    #
    # This middleware handles development-specific functionality:
    # 1. Validates Rack compliance using Rack::Lint
    # 2. Sets up a proxy to a local Vite frontend development server
    # 3. Configures hot module reloading for frontend development
    # 4. Enables automatic code reloading via Rack::Reloader
    #
    # Only activated in development mode, this middleware provides a clean separation
    # of development concerns from the main application stack.
    #
    class ViteProxy
      # The wrapped Rack application
      # @return [#call] The Rack application instance passed to this middleware
      attr_reader :app

      # Initialize the Vite proxy middleware for development
      #
      # @param app [#call] The Rack application to wrap
      def initialize(app)
        @app = app
        @rack_app = setup_proxy
      end

      # Process an HTTP request through the development middleware stack
      # Routes frontend asset requests to Vite dev server when configured
      #
      # @param env [Hash] Rack environment hash containing request information
      # @return [Array] Standard Rack response array [status, headers, body]
      def call(env)
        @rack_app.call(env)
      end

      private

      # Configure the development middleware stack with Vite proxy
      #
      # Creates a Rack middleware stack that includes:
      # - Rack::Lint for validating Rack compliance
      # - Conditional Vite dev server proxy based on configuration
      # - Rack::Reloader for automatic code reloading
      #
      # @return [#call] Configured Rack application for development
      def setup_proxy
        # Store reference to original app for use inside builder block
        # This is necessary because the Rack::Builder block runs in a different context
        app_instance = @app

        Rack::Builder.new do
          # Enable Rack compliance validation in development
          # This helps catch middleware issues early
          use Rack::Lint

          # Retrieve development configuration settings
          config = Onetime.conf.fetch(:development, {})

          # Configure Vite proxy based on settings
          case config
          in {enabled: true, frontend_host: String => frontend_host}
            if frontend_host.strip.empty?
              Onetime.ld "[ViteProxy] No frontend host configured to proxy"
            else
              Onetime.li "[ViteProxy] Using frontend proxy for /dist to #{frontend_host}"
              require 'rack/proxy'

              # Define anonymous proxy class for Vite dev server
              # This selectively forwards only /dist/ requests to Vite
              proxy_klass = Class.new(Rack::Proxy) do
                define_method(:perform_request) do |env|
                  case env['PATH_INFO']
                  when %r{\A/dist/} then super(env.merge('REQUEST_PATH' => env['PATH_INFO']))
                  else @app.call(env)
                  end
                end
              end

              # Add the proxy to the middleware stack
              use proxy_klass, backend: frontend_host
            end
          else
            Onetime.ld "[ViteProxy] Frontend proxy disabled"
          end

          # Enable automatic code reloading with 1 second check interval
          use Rack::Reloader, 1

          # All requests eventually pass through to the original application
          run ->(env) { app_instance.call(env) }
        end.to_app
      end
    end
  end
end
