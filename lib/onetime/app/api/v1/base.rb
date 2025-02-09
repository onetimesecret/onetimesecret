# Ensure no conflicts with Onetime::App::API::Base methods
require_relative '../../app_helpers'   # app/helpers.rb


module Onetime::App
  class API

    module Base
      include Onetime::App::WebHelpers

      def publically
        carefully do
          check_locale!
          yield
        end
      end

      # curl -F 'ttl=7200' -u 'EMAIL:APITOKEN' http://LOCALHOSTNAME:3000/api/v1/generate
      def authorized allow_anonymous=false
        carefully(redirect=nil, content_type='application/json', app: :api) do
          check_locale!

          req.env['otto.auth'] ||= Rack::Auth::Basic::Request.new(req.env)
          auth = req.env['otto.auth']

          # First line, check for basic auth
          if auth.provided?
            raise OT::Unauthorized unless auth.basic?

            custid, apitoken = *(auth.credentials || [])
            raise OT::Unauthorized if custid.to_s.empty? || apitoken.to_s.empty?

            return disabled_response(req.path) unless authentication_enabled?

            OT.ld "[authorized] Attempt for '#{custid}' via #{req.client_ipaddress} (basic auth)"
            possible = OT::Customer.load custid
            raise OT::Unauthorized, "No such customer" if possible.nil?

            @cust = possible if possible.apitoken?(apitoken)
            raise OT::Unauthorized, "Invalid credentials" if cust.nil? # wrong token

            @sess = cust.load_or_create_session req.client_ipaddress

            # Set the session as authenticated for this request
            sess.authenticated = true

            OT.ld "[authorized] '#{custid}' via #{req.client_ipaddress} (#{sess.authenticated?})"

          # Second line, check for session cookie. We allow this in certain cases
          # like API requests coming from hybrid Vue components.
          elsif req.cookie?(:sess)

            check_session!

            unless sess.authenticated? || allow_anonymous
              raise OT::Unauthorized, "Session not authenticated"
            end

            # Only attempt to load the customer object if the session has
            # already been authenticated. Otherwise this is an anonymous session.
            @cust = sess.load_customer if sess.authenticated?
            @cust ||= Customer.anonymous if allow_anonymous

            raise OT::Unauthorized, "Invalid credentials" if cust.nil? # wrong token

            custid = @cust.custid unless @cust.nil?
            OT.ld "[authorized] '#{custid}' via #{req.client_ipaddress} (cookie)"

            # Anytime we allow session cookies, we must also check shrimp. This will
            # run only for POST etc requests (i.e. not GET) and it's important to
            # check the shrimp after checking auth. Otherwise we'll chrun through
            # shrimp even though weren't going to complete the request anyway.
            check_shrimp!

          # Otherwise, we have no credentials, so we must be anonymous. Only
          # methods that opt-in to allow anonymous sessions will be allowed to
          # proceed.
          else

            unless allow_anonymous
              raise OT::Unauthorized, "No session or credentials"
            end

            @cust = OT::Customer.anonymous
            @sess = OT::Session.new req.client_ipaddress, cust.custid

            if OT.debug?
              ip_address = req.client_ipaddress.to_s
              session_id = sess.sessid.to_s
              message = "[authorized] Anonymous session via #{ip_address} (new session #{session_id})"
              OT.ld message
            end

          end

          if cust.nil? || sess.nil?
            raise OT::Unauthorized, "[bad-cust] '#{custid}' via #{req.client_ipaddress}"
          end

          yield
        end
      end

      # Determine and set the locale for the current request.
      #
      # This method prioritizes locales in the following order:
      # 1. Query parameter 'locale'
      # 2. Provided 'locale' argument
      # 3. Rack environment's 'rack.locale'
      # 4. Customer's locale (if available)
      # 5. First configured locale
      #
      # The method also ensures that only supported locales are used.
      #
      # @param locale [String, nil] Optional locale to use (overridden by query parameter)
      # @return [void]
      def check_locale!(locale = nil)
        # Check for locale in query parameters
        unless req.params[:locale].to_s.empty?
          locale = req.params[:locale]
          # Set locale cookie if query parameter is present
          is_secure = Onetime.conf.dig(:site, :ssl)
          res.send_cookie :locale, locale, 30.days, is_secure
        end

        # Initialize locales array
        locales = req.env['rack.locale'] || []  # Requested list from Rack

        # Add provided locale to the beginning of the list
        # Support both en and en-US
        locales.unshift(locale.split('-').first) if locale.is_a?(String)

        # Add customer's locale if available
        locales << cust.locale if cust&.locale?

        # Ensure at least one configured locale is available
        locales << OT.locales.first

        # Filter and clean up locales
        locales = locales.uniq.reject { |l| !OT.locales.key?(l) }.compact

        # Set default locale if the current one is not supported
        locale = locales.first unless OT.locales.key?(locale)

        # Set locale in the request environment
        req.env['ots.locale'] = @locale = locale
        req.env['ots.locales'] = locales
      end


      def json hsh
        res.header['Content-Type'] = "application/json; charset=utf-8"
        res.body = hsh.to_json
      end

      def json_success hsh
        # A convenience method that returns JSON success and adds a
        # fresh shrimp to the response body. The fresh shrimp is
        # helpful for parts of the Vue UI that get a successful
        # response and don't need to refresh the entire page.
        json success: true, shrimp: sess.add_shrimp, **hsh
      end

      def handle_form_error ex, hsh={}
        # We get here mainly from rescuing `OT::FormError` in carefully
        # which is used by both the web and api endpoints. When carefully
        # is called with `redirect=nil` (100% of the time for api), that
        # nil value gets passed through to here. I could swear we already
        # fixed this. Anyway, since this only impacts shrimp we can just
        # double up the guardrailing here to make sure we have a hash
        # to work with. Not ideal though.
        hsh ||= {}
        # We don't get here from a form error unless the shrimp for this
        # request was good. Pass a delicious fresh shrimp to the client
        # so they can try again with a new one (without refreshing the
        # entire page).
        hsh[:shrimp] = sess.add_shrimp
        error_response ex.message, hsh
      end

      def secret_not_found_response
        not_found_response "Unknown secret", :secret_key => req.params[:key]
      end

      def disabled_response path
        not_found_response "#{path} is not available"
      end

      def not_found_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end

      # The v1 API historically returned 404 for auth errors
      def not_authorized_error hsh={}
        hsh[:message] = "Not authorized"
        res.status = 404
        json hsh
      end

      def error_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end
      alias throttle_response error_response # Maintain existing behaviour

    end
  end
end
