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

      # curl -F 'ttl=7200' -u 'EMAIL:APIKEY' http://LOCALHOSTNAME:3000/api/v1/generate
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

            custid = @cust.custid unless @cust.nil?
            OT.info "[authorized] '#{custid}' via #{req.client_ipaddress} (cookie)"

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

      # Retrieves and lists records of the specified class. Also used for single
      # records. It's up to the logic class what it wants to return via
      # `logic.success_data`` (i.e. `record: {...}` or `records: [...]`` ).
      #
      # @param record_class [Class] The ActiveRecord class of the records to be retrieved.
      # @param error_message [String] The error message to display if retrieval fails.
      #
      # @return [void]
      #
      # @example
      #   retrieve_records(User, "Unable to retrieve users")
      #
      def retrieve_records(logic_class)
        authorized do
          OT.ld "[retrieve] #{logic_class}"
          logic = logic_class.new(sess, cust, req.params, locale)
          logic.raise_concerns
          logic.process
          json success: true, **logic.success_data
        end
      end

      # Processes an action using the specified logic class and handles the response.
      #
      # @param logic_class [Class] The class implementing the action logic.
      # @param error_message [String] The error message to display if the action fails.
      #
      # The logic class must implement the following methods:
      # - raise_concerns
      # - process_params
      # - process
      # - greenlighted
      # - success_data
      #
      # @yield [logic] Gives access to the logic object for custom success handling.
      # @yieldparam logic [Object] The instantiated logic object after processing.
      #
      # @return [void]
      #
      # @example
      #   process_action(OT::Logic::GenerateAPIkey, "API Key could not be generated.") do |logic|
      #     json_success(custid: cust.custid, apikey: logic.apikey)
      #   end
      #
      def process_action(logic_class, success_message, error_message)
        authorized do
          logic = logic_class.new(sess, cust, req.params, locale)
          logic.raise_concerns
          logic.process
          OT.ld "[process_action] #{logic_class} success=#{logic.greenlighted}"
          if logic.greenlighted
            json_success(custid: cust.custid, **logic.success_data)
          else
            error_response(error_message)
          end
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

      def error_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end

    end
  end
end
