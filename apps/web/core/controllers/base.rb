# frozen_string_literal: true

require_relative '../views'
require 'onetime/helpers/session_helpers'
require 'onetime/helpers/shrimp_helpers'

module Core
  module Controllers
    module Base
      include Onetime::Logging
      include Onetime::Helpers::SessionHelpers
      include Onetime::Helpers::ShrimpHelpers

      attr_reader :req, :res, :locale

      def initialize(req, res)
        @req    = req
        @res    = res
        @locale = req.locale
      end

      # Access the current customer from Otto auth middleware or session
      def cust
        @cust ||= load_current_customer
      end

      # Access the current session
      def session
        req.env['rack.session']
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
          http_logger.error "Invalid URI in URL validation",
            exception: ex,
            url: url
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
        view       = Core::Views::VuePoint.new(req, session, cust, locale)
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
        body = { error: message }
        body['field-error'] = field_error if field_error
        json_response(body, status: status)
      end

      # Common page rendering methods

      def index
        view     = Core::Views::VuePoint.new(req, session, cust, locale)
        res.body = view.render
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
      # that executed for the current route (noauth, sessionauth, colonelsonly, etc.)
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
        http_logger.error "Failed to load customer",
          exception: ex
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
        http_logger.error "Form error occurred",
          exception: ex,
          field: field,
          redirect_path: redirect_path
        if json_requested?
          # FormError must provide field and error_type
          field ||= ex.field
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
            http_logger.debug "Capturing error to Sentry with request headers",
              headers: headers
          end

          Sentry.capture_exception(error, level: level, &)
        rescue NoMethodError => ex
          raise unless ex.message.include?('start_with?')

          http_logger.error "Sentry capture error (NoMethodError)",
            exception: ex
        rescue StandardError => ex
          http_logger.error "Sentry capture error",
            exception: ex
        end
      end

      def capture_message(message, level = :log, &)
        return unless OT.d9s_enabled

        Sentry.capture_message(message, level: level, &)
      rescue StandardError => ex
        http_logger.error "Sentry capture_message error",
          exception: ex,
          message: message
      end
    end
  end
end
