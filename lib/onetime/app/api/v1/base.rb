# Ensure no conflicts with Onetime::App::API::Base methods
require_relative '../../helpers'   # app/helpers.rb


class Onetime::App
  class API

    module Base
      include Onetime::App::Helpers

      def publically
        carefully do
          check_locale!
          yield
        end
      end

      # curl -F 'ttl=7200' -u 'EMAIL:APIKEY' http://LOCALHOSTNAME:3000/api/v1/generate
      def authorized allow_anonymous=false
        carefully(redirect=nil, content_type='application/json') do
          check_locale!

          req.env['otto.auth'] ||= Rack::Auth::Basic::Request.new(req.env)
          auth = req.env['otto.auth']

          # First line, check for basic auth
          if auth.provided?
            raise OT::Unauthorized unless auth.basic?

            custid, apitoken = *(auth.credentials || [])
            raise OT::Unauthorized if custid.to_s.empty? || apitoken.to_s.empty?

            possible = OT::Customer.load custid
            raise OT::Unauthorized if possible.nil?

            @cust = possible if possible.apitoken?(apitoken)

            unless cust.nil? || @sess = cust.load_session
              @sess = OT::Session.create req.client_ipaddress, cust.custid
            end

            sess.authenticated = true unless sess.nil?

            OT.info "[authorized] '#{custid}' via #{req.client_ipaddress} (#{sess.authenticated?})"

          # Second line, check for session cookie. We allow this in certain cases
          # like API requests coming from hybrid Vue components.
          elsif req.cookie?(:sess)

            # Anytime we allow session cookies, we must also check shrimp.
            check_session!
            check_shrimp!

            # Only attempt to load the customer object if the session has
            # already been authenticated. Otherwise this is an anonymous session.
            @cust = sess.load_customer if sess.authenticated?

          #custid = @cust.custid unless @cust.nil?
          #OT.info "[authorized] '#{custid}' via #{req.client_ipaddress} (cookie)"

          # Otherwise, we have no credentials, so we must be anonymous. Only
          # methods that opt-in to allow anonymous sessions will be allowed to
          # proceed.
          else

            if allow_anonymous
              @cust = OT::Customer.anonymous
              @sess = OT::Session.new req.client_ipaddress, cust.custid
              OT.info "[authorized] Anonymous session via #{req.client_ipaddress} (new session #{sess.sessid})"
            else
              raise OT::Unauthorized, "No session or credentials"
            end

          end

          if cust.nil? || sess.nil?
            raise OT::Unauthorized, "[bad-cust] '#{custid}' via #{req.client_ipaddress}"
          end

          # TODO: Have a look through this codepath and see if we can remove it.
          cust.sessid = sess.sessid unless cust.anonymous?

          yield
        end
      end

      # Find the locale of the request based on req.env['rack.locale'],
      # which is set automatically by Otto v0.4.0 and greater.
      #
      # If `locale` is specified, it will override if the locale is supported.
      # If the `locale` query param is set, it will override.
      #
      # @param locale [String] the locale to use, defaults to nil
      # @return [void]
      def check_locale! locale=nil
        unless req.params[:locale].to_s.empty?
          locale = req.params[:locale]                                 # Use query param
          res.send_cookie :locale, locale, 30.days, Onetime.conf[:site][:ssl]
        end
        locales = req.env['rack.locale'] || []                          # Requested list
        locales.unshift locale.split('-').first if locale.is_a?(String) # Support both en and en-US
        locales << OT.conf[:locales].first                              # Ensure at least one configured locale is available
        locales = locales.uniq.reject { |l| !OT.locales.has_key?(l) }.compact
        locale = locales.first if !OT.locales.has_key?(locale)           # Default to the first available
        req.env['ots.locale'], req.env['ots.locales'] = (@locale = locale), locales
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

      def not_found_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end

      def error_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end

    end
  end
end
