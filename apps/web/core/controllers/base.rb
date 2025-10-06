# frozen_string_literal: true

require_relative '../views'

module Core
  module Controllers
    module Base
      include Core::ControllerHelpers

      attr_reader :req, :res, :locale

      def initialize(req, res)
        @req = req
        @res = res
        @locale = req.env['ots.locale'] || 'en'
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
        rescue URI::InvalidURIError
          # Log an error message if the URL is invalid
          OT.le "[validate_url] Invalid URI: #{uri}"
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

      # Common page rendering methods

      def index
        view     = Core::Views::VuePoint.new(req, session, cust, locale)
        res.body = view.render
      end

      def customers_only
        res.no_cache!
        view     = Core::Views::VuePoint.new(req, session, cust, locale)
        res.body = view.render
      end

      def colonels_only
        res.no_cache!
        view     = Core::Views::VuePoint.new(req, session, cust, locale)
        res.body = view.render
      end

      private

      def load_current_customer
        # Try Otto auth result first (set by auth middleware)
        if req.env['otto.user']
          user = req.env['otto.user']
          return user if user.is_a?(Onetime::Customer)
        end

        # Fallback to anonymous
        Onetime::Customer.anonymous
      rescue StandardError => ex
        OT.le "[base_controller] Failed to load customer: #{ex.message}"
        Onetime::Customer.anonymous
      end
    end
  end
end
