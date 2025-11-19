# apps/web/core/controllers/base.rb
#
# frozen_string_literal: true

require_relative '../views'
require 'onetime/helpers/session_helpers'
require 'onetime/helpers/shrimp_helpers'
require 'onetime/controllers/organization_context'

module Core
  module Controllers
    module Base
      include Onetime::LoggerMethods
      include Onetime::Helpers::SessionHelpers
      include Onetime::Helpers::ShrimpHelpers
      include Onetime::Controllers::OrganizationContext

      attr_reader :req, :res, :locale

      def initialize(req, res)
        @req    = req
        @res    = res
        @locale = req.locale
      end

      def index
        # Check for header-based homepage protection before rendering
        # This sets a flag in the request env that the view layer can serialize
        req.env['onetime.homepage_mode'] = check_protected_by_request_header

        # Simplified: BaseView now extracts everything from req
        view     = Core::Views::VuePoint.new(req)
        res.body = view.render
      end

      # Access the current customer from Otto auth middleware or session
      def cust
        @cust ||= load_current_customer
      end

      # Access the current session
      def session
        req.env['rack.session']
      end

      # Check if the request contains the homepage protection header
      #
      # When site.interface.ui.homepage.mode=protected, this
      # checks if the configured HTTP header contains the value 'protected'.
      # Returns true when the header matches, nil otherwise.
      #
      # SECURITY:
      # - The request header can only RESTRICT access, never EXPAND it. It has
      #   not effect on authentication settings or API routes.
      # - The frontend Vue router checks homepage_mode determine homepage state
      #
      # @return [Boolean, nil] true if header matches 'protected', nil otherwise
      def check_protected_by_request_header
        ui_config = OT.conf.dig('site', 'interface', 'ui') || {}
        homepage_mode = ui_config.dig('homepage', 'mode')
        homepage_request_header = ui_config.dig('homepage', 'request_header')

        http_logger.debug '[check_protected_by_request_header] check initiated with settings', {
          mode: homepage_mode,
          header_name: homepage_request_header,
        }

        return nil unless homepage_mode == 'protected'

        # Require request_header to be configured
        return nil if homepage_request_header.nil? || homepage_request_header.empty?

        # Normalize header name to HTTP_* format for env lookup
        # Convert dashes to underscores and prepend HTTP_ if not present
        header_key = homepage_request_header.upcase.tr('-', '_')
        header_key = "HTTP_#{header_key}" unless header_key.start_with?('HTTP_')

        # Get the actual header value from the request
        header_value = req.env[header_key]

        http_logger.debug '[check_protected_by_request_header] protection header value', {
          header_key: header_key,
          header_present: !header_value.nil?,
          header_empty: header_value&.empty?,
        }

        # Return nil if header is missing or empty
        return nil if header_value.nil? || header_value.empty?

        # Check for exact match with 'protected' (case-sensitive and set to
        # a literal value for safety, security, and peace of mind).
        header_value == 'protected' ? 'protected' : nil
      end

      # Validates a given URL and ensures it can be safely redirected to.
      #
      # @param url [String] the URL to validate
      # @return [URI::HTTP, nil] the validated URI object if valid, otherwise nil
      def validate_url(url)
        # This is named validate_url and not validate_uri because we aim to return
        # an appropriate value that can be safely redirected to. A path or other portion
        # of a URI can't be properly validated whereas a complete URL describes a
        # specific location to attempt to navigate to.
        uri = nil
        begin
          # Attempt to parse the URL
          uri = URI.parse(url)
        rescue URI::InvalidURIError => ex
          # Log an error message if the URL is invalid
          http_logger.error 'Invalid URI in URL validation', {
            exception: ex,
            url: url,
          }
        else
          # Set a default host if the host is missing
          uri.host ||= OT.conf['site']['host']
          # Ensure the scheme is HTTPS if SSL is enabled in the configuration
          if (OT.conf['site']['ssl']) && (uri.scheme.nil? || uri.scheme != 'https')
            uri.scheme = 'https'
          end
          # Set uri to nil if it is not an HTTP or HTTPS URI
          uri        = nil unless uri.is_a?(URI::HTTP)
          # Log an info message with the validated URI
          OT.info "[validate_url] Validated URI: #{uri}"
        end

        # Return the validated URI or nil if invalid
        uri
      end

      def not_found
        not_found_response ''
      end

      def server_error(status = 500, _message = nil)
        res.status          = status
        res['content-type'] = 'text/html'
        res.body            = <<-HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>500 Internal Server Error</title>
        </head>
        <body>
            <h1>500 - Internal Server Error</h1>
            <p>Something went wrong on our end. Please try again later.</p>
        </body>
        </html>
        HTML
      end

      # Handles requests for routes that don't match any defined server-side
      # routes. Instead of returning a 404 status, it serves the entrypoint
      # HTML for the Vue.js SPA.
      #
      # @param message [String, nil] An optional error message to be added to the view.
      #
      # @return [void]
      #
      # This method follows the best practice for serving Single Page Applications:
      # 1. It serves the same entrypoint HTML for all non-API routes.
      # 2. It allows the Vue.js router to handle client-side routing and 404 logic.
      #
      # Rationale:
      # - Enables deep linking and direct access to any SPA route.
      # - Supports client-side routing without server knowledge of Vue.js routes.
      # - Simplifies server configuration and maintenance.
      # - Allows for proper handling of 404s within the Vue.js application.
      def not_found_response(message, **)
        # Simplified: BaseView now extracts everything from req
        view       = Core::Views::VuePoint.new(req)
        view.add_error(message) unless message&.empty?
        res.status = 404
        res.body   = view.render  # Render the entrypoint HTML
      end

      # JSON response helpers
      #
      # These methods return Hash objects that will be serialized by Otto's JSONHandler
      # when the route has response=json. Do not manually set res.body for JSON responses.

      def json_response(data, status: 200)
        res.status = status
        data
      end

      def json_success(message, status: 200)
        json_response({ success: message }, status: status)
      end

      def json_error(message, field_error: nil, status: 400)
        body                = { error: message }
        body['field-error'] = field_error if field_error
        json_response(body, status: status)
      end

      protected

      def signin_enabled?
        auth_settings['enabled'] && auth_settings['signin']
      end

      def signup_enabled?
        auth_settings['enabled'] && auth_settings['signup']
      end

      private

      def auth_settings
        OT.conf.dig('site', 'authentication')
      end

      # Returns the StrategyResult created by Otto's RouteAuthWrapper
      #
      # This provides authenticated state and metadata from the auth strategy
      # that executed for the current route (noauth, sessionauth, basicauth, etc.)
      #
      # RouteAuthWrapper (post-routing authentication) executes the strategy and sets
      # req.env['otto.strategy_result'] before the controller handler runs.
      #
      # @return [Otto::Security::Authentication::StrategyResult]
      def strategy_result
        req.env['otto.strategy_result']
      end

      def load_current_customer
        # Use Rack::Request extension method (delegates to strategy_result.user)
        user = req.user
        return user if user.is_a?(Onetime::Customer)

        # Fallback to anonymous
        Onetime::Customer.anonymous
      rescue StandardError => ex
        http_logger.error 'Failed to load customer', {
          exception: ex,
        }
        Onetime::Customer.anonymous
      end

      # Checks if authentication is enabled for the site.
      #
      # @return [Boolean] True if authentication and sign-in are enabled, false otherwise.
      def authentication_enabled?
        authentication_enabled = OT.conf['site']['authentication']['enabled'] rescue false # rubocop:disable Style/RescueModifier
        signin_enabled         = OT.conf['site']['authentication']['signin'] rescue false # rubocop:disable Style/RescueModifier
        authentication_enabled && signin_enabled
      end

      # Checks if the request accepts JSON responses
      #
      # @return [Boolean] True if the Accept header includes application/json
      def json_requested?
        req.env['HTTP_ACCEPT']&.include?('application/json')
      end

      # Executes logic with standardized error handling for both JSON and HTML responses
      #
      # @param logic [Object] Logic object to execute
      # @param success_message [String] Success message for JSON responses
      # @param success_redirect [String] Path to redirect on success (HTML)
      # @param error_redirect [String, nil] Path to redirect on error (HTML), nil to re-raise
      # @yield Optional block for additional processing after logic.process
      # @return [Hash, nil] JSON response Hash for routes with response=json, nil otherwise
      def execute_with_error_handling(logic, success_message:, success_redirect: '/', error_redirect: nil, error_status: 400)
        logic.raise_concerns
        logic.process
        yield if block_given?

        if json_requested?
          json_success(success_message)
        else
          res.redirect success_redirect
          nil
        end
      rescue OT::FormError => ex
        handle_form_error(ex, error_redirect, status: error_status)
      end

      # Handles form errors with appropriate JSON or HTML response
      #
      # @param ex [OT::FormError] The form error exception
      # @param redirect_path [String, nil] Path to redirect for HTML, nil to re-raise
      # @param field [String, nil] Field name for error, nil to infer from message
      # @return [Hash, nil] JSON error Hash for routes with response=json, nil otherwise
      def handle_form_error(ex, redirect_path = nil, field: nil, status: 400)
        # We pass the message here and not the exception itelf b/c SemanticLogger
        # automatically outputs backtrace when it receives one.
        http_logger.error 'Form error occurred', {
          message: ex.message,
          field: field || ex.field,
          error_type: ex.error_type,
          redirect_path: redirect_path,
        }
        if json_requested?
          # FormError must provide field and error_type
          field    ||= ex.field
          error_type = ex.error_type || ex.message.downcase

          json_error(ex.message, field_error: [field, error_type], status: status)
        elsif redirect_path
          session['error_message'] = ex.message
          res.redirect redirect_path
          nil
        else
          raise
        end
      end

      # Sentry error tracking
      #
      # Available levels are :fatal, :error, :warning, :log, :info, and :debug.
      # The Sentry default, if not specified, is :error.
      def capture_error(error, level = :error, &)
        return unless OT.d9s_enabled

        begin
          if defined?(req) && req.respond_to?(:env)
            headers = req.env.select { |k, _v| k.start_with?('HTTP_') rescue false } # rubocop:disable Style/RescueModifier
            http_logger.debug 'Capturing error to Sentry with request headers', {
              headers: headers,
            }
          end

          Sentry.capture_exception(error, level: level, &)
        rescue NoMethodError => ex
          raise unless ex.message.include?('start_with?')

          http_logger.error 'Sentry capture error (NoMethodError)', {
            exception: ex,
          }
        rescue StandardError => ex
          http_logger.error 'Sentry capture error', {
            exception: ex,
          }
        end
      end

      def capture_message(message, level = :log, &)
        return unless OT.d9s_enabled

        Sentry.capture_message(message, level: level, &)
      rescue StandardError => ex
        http_logger.error 'Sentry capture_message error', {
          exception: ex,
          message: message,
        }
      end
    end
  end
end
