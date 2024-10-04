require_relative '../app_helpers'

module Onetime
  module App

    module Base
      include OT::App::WebHelpers

      def publically redirect=nil
        carefully(redirect) do
          check_session!     # 1. Load or create the session, load customer (or anon)
          check_locale!      # 2. Check the request for the desired locale
          check_shrimp!      # 3. Check the shrimp for POST,PUT,DELETE (after session)
          check_referrer!    # 4. Check referrers for public requests
          yield
        end
      end

      def authenticated redirect=nil
        carefully(redirect) do
          no_cache!
          check_session!     # 1. Load or create the session, load customer (or anon)
          check_locale!      # 2. Check the request for the desired locale

          # We need the session so that cust is set to anonymous (and not
          # nil); we want locale too so that we know what language to use.
          # If this is a POST request, we don't need to check the shrimp
          # since it wouldn't change our response either way.
          return disabled_response(req.path) unless authentication_enabled?

          sess.authenticated? ? yield : res.redirect(('/'))
          check_shrimp!      # 3. Check the shrimp for POST,PUT,DELETE (after session and auth check)
        end
      end

      def colonels redirect=nil
        carefully(redirect) do
          no_cache!
          check_session!     # 1. Load or create the session, load customer (or anon)
          check_locale!      # 2. Check the request for the desired locale

          # We need the session so that cust is set to anonymous (and not
          # nil); we want locale too so that we know what language to use.
          # If this is a POST request, we don't need to check the shrimp
          # since it wouldn't change our response either way.
          return disabled_response(req.path) unless authentication_enabled?

          check_shrimp!      # 3. Check the shrimp for POST,PUT,DELETE (after session)

          is_allowed = sess.authenticated? && cust.role?(:colonel)
          is_allowed ? yield : raise(OT::Unauthorized, "Colonels only")
        end
      end

      def check_referrer!
        return if @check_referrer_ran
        @check_referrer_ran = true
        unless req.referrer.nil?
          OT.ld("[check-referrer] #{req.referrer} (#{req.referrer.class}) - #{req.path}")
        end
        return if req.referrer.nil? || req.referrer.match(Onetime.conf[:site][:host])
        sess.referrer ||= req.referrer

        # Don't allow a pesky error here from preventing the
        # request. Typically we don't want to be so hush hush
        # but this method is partiaularly important for receuving
        # redirects back from 3rd-party workflows like a new Stripe
        # subscription.
      rescue StandardError => ex
        backtrace = ex.backtrace.join("\n")
        OT.le "[check_referrer!] Caught error but continuing #{ex}: #{backtrace}"
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
          uri.host ||= OT.conf[:site][:host]
          # Ensure the scheme is HTTPS if SSL is enabled in the configuration
          if OT.conf[:site][:ssl]
            uri.scheme = 'https' if uri.scheme.nil? || uri.scheme != 'https'
          end
          # Set uri to nil if it is not an HTTP or HTTPS URI
          uri = nil unless uri.is_a?(URI::HTTP)
          # Log an info message with the validated URI
          OT.info "[validate_url] Validated URI: #{uri}"
        end

        # Return the validated URI or nil if invalid
        uri
      end

      def handle_form_error ex, redirect
        # We store the form fields temporarily in the session so
        # that the form can be pre-populated after the redirect.
        sess.set_form_fields ex.form_fields
        sess.set_error_message ex.message
        res.redirect redirect
      end

      def secret_not_found_response
        view = Onetime::App::Views::UnknownSecret.new req, sess, cust, locale
        res.status = 404
        res.body = view.render
      end

      def not_found
        publically do
          not_found_response ""
        end
      end

      def server_error status=500, message=nil
        res.status = status
        res['Content-Type'] = 'text/html'
        res.body = <<-HTML
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

      def disabled_response path
        error_response "#{path} is not available"
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
      # 1. It returns a 200 status code instead of 404 for unknown web routes.
      # 2. It serves the same entrypoint HTML for all non-API routes.
      # 3. It allows the Vue.js router to handle client-side routing and 404 logic.
      #
      # Rationale:
      # - Enables deep linking and direct access to any SPA route.
      # - Supports client-side routing without server knowledge of Vue.js routes.
      # - Simplifies server configuration and maintenance.
      # - Allows for proper handling of 404s within the Vue.js application.
      def not_found_response(message)
        view = Onetime::App::Views::VuePoint.new(req, sess, cust, locale)
        view.add_error(message) unless message&.empty?
        res.status = 200  # Always return 200 OK for SPA routes
        res.body = view.render  # Render the entrypoint HTML
      end

      def error_response message
        view = Onetime::App::Views::Error.new req, sess, cust, locale
        view.add_error message
        res.status = 401
        res.body = view.render
      end

    end
  end

end
