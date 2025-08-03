# lib/onetime/middleware/static_files.rb
#
# Static file serving middleware for the Onetime Secret application.
# Provides static file serving capabilities which can be used when
# running without a reverse proxy.

require 'rack'

module Onetime
  module Middleware
    # Static file serving middleware for Onetime Secret in production
    #
    # This middleware handles serving static assets in production environments:
    # - Serves files from the public/web directory
    # - Handles common static paths like /dist, /img, etc.
    # - Enables the Vue frontend to be served in a production environment
    #
    # While a reverse proxy (like nginx) often handles static files in production,
    # this middleware provides fallback capability for simpler deployments.
    #
    class StaticFiles
      # The wrapped Rack application
      # @return [#call] The Rack application instance passed to this middleware
      attr_reader :app

      # Initialize the static files middleware
      #
      # @param app [#call] The Rack application to wrap
      def initialize(app)
        @app      = app
        @rack_app = setup_static_files
      end

      # Process an HTTP request through the static files middleware stack
      # Serves static files if path matches, otherwise delegates to the app
      #
      # @param env [Hash] Rack environment hash containing request information
      # @return [Array] Standard Rack response array [status, headers, body]
      def call(env)
        @rack_app.call(env)
      end

      private

      # Configure the static file serving middleware stack
      #
      # Creates a Rack middleware stack that serves static files from specific paths
      # and delegates all other requests to the wrapped application.
      #
      # @return [#call] Configured Rack application with static file handling
      def setup_static_files
        # Store reference to original app for use inside builder block
        # This is necessary because the Rack::Builder block runs in a different context
        app_instance        = @app
        middleware_settings = Onetime.conf.dig('experimental', 'middleware') || {}

        Rack::Builder.new do
          # Configure static file middleware to serve files from public/web directory
          # Only serve specific paths that contain static assets
          if middleware_settings[:static_files]
            Onetime.ld '[StaticFiles] Enabling StaticFiles middleware'
            use Rack::Static,
              urls: ['/dist', '/img', '/v3', '/site.webmanifest', '/favicon.ico'],
              root: 'public/web'
          end

          # All non-static requests pass through to the original application
          run ->(env) { app_instance.call(env) }
        end.to_app
      end
    end
  end
end
