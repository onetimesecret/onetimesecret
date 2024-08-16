require_relative '../helpers'  # app/helpers.rb

module Onetime
  class App

    module Base
      include OT::App::Helpers

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

          check_shrimp!      # 3. Check the shrimp for POST,PUT,DELETE (after session)
          sess.authenticated? ? yield : res.redirect(('/'))
        end
      end

      def colonels redirect=nil
        carefully(redirect) do
          check_session!     # 1. Load or create the session, load customer (or anon)
          check_locale!      # 2. Check the request for the desired locale

          # See explanation in `authenticated` method
          return disabled_response(req.path) unless authentication_enabled?

          check_shrimp!      # 3. Check the shrimp for POST,PUT,DELETE (after session)
          sess.authenticated? && cust.role?(:colonel) ? yield : res.redirect(('/'))
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
        sess.set_form_fields ex.form_fields  # to pre-populate the form
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

      def server_error
        publically do
          error_response "You found a bug. Let us know how it happened!"
        end
      end

      def disabled_response path
         not_found_response "#{path} is not available"
      end

      def not_found_response message
        view = Onetime::App::Views::NotFound.new req, sess, cust, locale
        view.add_error message
        res.status = 404
        res.body = view.render
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
