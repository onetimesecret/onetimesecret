# lib/onetime/middleware/security.rb
#
# frozen_string_literal: true

#
# Security middleware collection for the Onetime Secret application.
# Configures various Rack::Protection middleware components based on
# application configuration settings.

require 'rack'
require 'rack/protection'
require 'rack/utf8_sanitizer'

require_relative 'registry'

module Onetime
  module Middleware
    # Security middleware collection for Onetime Secret
    #
    # This middleware provides a centralized configuration for various
    # security-related Rack middleware components:
    # - UTF-8 sanitization to prevent encoding-based attacks
    # - Protection against CSRF via HTTP Origin validation
    # - Parameter escaping to prevent XSS attacks
    # - XSS protection headers
    # - Frame options to prevent clickjacking
    # - Path traversal protection
    # - IP spoofing protection
    # - Strict Transport Security configuration
    #
    # Each protection can be individually enabled/disabled via configuration.
    #
    # Cookie tossing prevention is not mounted here: it must run above
    # Onetime::Session, and MiddlewareStack mounts it there.
    #
    class Security
      # The components this wrapper mounts, in mount order. The definitions
      # themselves live in Onetime::Middleware::Registry, the single component
      # table; this list selects the Security subset.
      COMPONENT_NAMES = %w[
        UTF8Sanitizer
        AuthenticityToken
        HttpOrigin
        XSSHeader
        FrameOptions
        PathTraversal
        IPSpoofing
        StrictTransport
      ].freeze

      # Middleware keys for which project guidance says a disabled toggle should
      # be reviewed. Derived from the Registry flags; this is distinct from the
      # operator configuration that determines whether the component is mounted.
      WARN_WHEN_DISABLED_KEYS = COMPONENT_NAMES
        .map { |name| Registry.fetch(name) }
        .select { |cfg| cfg[:warn_when_disabled] }
        .map { |cfg| cfg[:key].to_s }
        .freeze

      # The wrapped Rack application
      # @return [#call] The Rack application instance passed to this middleware
      attr_reader :app

      # Initialize the security middleware
      #
      # @param app [#call] The Rack application to wrap
      def initialize(app)
        @app      = app
        @rack_app = setup_security_middleware
      end

      # Process an HTTP request through the security middleware stack
      #
      # @param env [Hash] Rack environment hash containing request information
      # @return [Array] Standard Rack response array [status, headers, body]
      def call(env)
        @rack_app.call(env)
      end

      private

      # Configure the security middleware stack based on application settings
      #
      # Reads configuration from Onetime.conf.dig("site", "middleware")
      # and conditionally enables corresponding Rack::Protection middleware.
      #
      # @return [#call] Configured Rack application with security middleware
      def setup_security_middleware
        # Store reference to original app for use inside builder block
        # This is necessary because the Rack::Builder block runs in a different context
        app_instance        = @app
        middleware_settings = Onetime.conf.dig('site', 'middleware') || {}

        # Define middleware components with their corresponding settings keys
        components               = self.class.middleware_components
        warn_when_disabled_keys  = WARN_WHEN_DISABLED_KEYS
        security                 = self.class
        Rack::Builder.new do
          # Apply each middleware if configured
          components.each do |name, config|
            # ERB in the config emits real YAML booleans (true/false), so this
            # reads a real boolean, not a string.
            middleware_key = config[:key].to_s
            unless middleware_settings[middleware_key]
              # Flag a disabled component when project guidance says the
              # operator's configuration choice merits review.
              if warn_when_disabled_keys.include?(middleware_key)
                security.warn_disabled(name, middleware_key)
              end
              next
            end

            OT.ld "[Security] Enabling #{name} protection (site.middleware.#{middleware_key})"

            # Use double-splat to pass options only if they exist
            use config[:klass], **(config[:options] || {})
          end

          # Pass through to original application
          run ->(env) { app_instance.call(env) }
        end.to_app
      end

      class << self
        # The Registry component table filtered to the components Security
        # mounts, preserving mount order. Kept as a method (same shape as the
        # former class-level hash) so existing consumers reading e.g.
        # middleware_components['AuthenticityToken'][:options][:allow_if]
        # keep working unchanged.
        #
        # @return [Hash] name => {key:, klass:, options:, warn_when_disabled:}
        def middleware_components
          @middleware_components ||= COMPONENT_NAMES
            .to_h { |name| [name, Registry.fetch(name)] }
            .freeze
        end

        # Warn that a component is disabled, once per process. Every
        # application mounts this middleware, so a warning per build repeats
        # the same line once per app at boot, and the spec suites, which
        # build the applications thousands of times, wrote enough of them to
        # push CI job logs past their size limit. The warning stays at warn
        # level so the operator still sees it in the startup log.
        #
        # No require_relative for MiddlewareStack: it mounts this middleware,
        # so the constant is loaded by the time anything builds it. A
        # standalone build without it warns on every build instead.
        #
        # @param name [String] component display name, e.g. 'FrameOptions'
        # @param key [String] the site.middleware toggle
        # @return [void]
        def warn_disabled(name, key)
          message = "[Security] #{name} protection DISABLED (site.middleware.#{key}=false)"
          if defined?(Onetime::Application::MiddlewareStack)
            Onetime::Application::MiddlewareStack.warn_once(:"security_#{key}_disabled", message)
          else
            OT.lw message
          end
        end
      end
    end
  end
end
