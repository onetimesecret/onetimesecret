# apps/api/v2/controllers/base.rb

require_relative 'class_settings'
require_relative 'helpers'
require 'altcha'

module V2
  module Controllers::Base
    include V2::ControllerHelpers
    include V2::Controllers::ClassSettings

    attr_reader :req, :res
    attr_reader :sess, :cust, :locale
    attr_reader :ignoreshrimp

    def initialize req, res
      @req, @res = req, res
    end

    def publically
      carefully do
        check_session!
        check_locale!
        yield
      end
    end

    def authorized allow_anonymous=false
      carefully(redirect=nil, content_type='application/json', app: :api) do # rubocop:disable Metrics/BlockLength,Metrics/PerceivedComplexity
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
          possible = V2::Customer.load custid
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
          @cust ||= V2::Customer.anonymous if allow_anonymous

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

          @cust = V2::Customer.anonymous
          @sess = V2::Session.new req.client_ipaddress, cust.custid

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

    # Ignores the allow_anonymous argument passed in
    def colonels _
      allow_anonymous = false
      authorized(allow_anonymous) do
        raise OT::Unauthorized, "No such customer" unless cust.role?(:colonel)
        yield
      end
    end

    # Retrieves and lists records of the specified class. Also used for single
    # records. It's up to the logic class what it wants to return via
    # `logic.success_data`` (i.e. `record: {...}` or `records: [...]`` ).
    #
    # @param logic_class [Class] The logic class for processing the request.
    # @param auth_type [Symbol] The authorization type to use (:authorized or :colonels).
    #
    # @return [void]
    #
    # @example
    #   retrieve_records(UserLogic)
    #   retrieve_records(SecretDocumentLogic, auth_type: :colonels)
    #
    def retrieve_records(logic_class, auth_type: :authorized, allow_anonymous: false)
      auth_method = auth_type == :colonels ? method(:colonels) : method(:authorized)

      auth_method.call(allow_anonymous) do
        OT.ld "[retrieve] #{logic_class}"
        logic = logic_class.new(sess, cust, req.params, locale)

        logic.domain_strategy = req.env['onetime.domain_strategy'] # never nil
        logic.display_domain = req.env['onetime.display_domain'] # can be nil

        OT.ld <<~DEBUG
          [retrieve_records]
            class:     #{logic_class}
            strategy:  #{logic.domain_strategy}
            display:   #{logic.display_domain}
        DEBUG

        logic.raise_concerns
        logic.process

        json success: true, **logic.success_data
      end
    end

    # Processes an action using the specified logic class and handles the response.
    #
    # @param logic_class [Class] The class implementing the action logic.
    # @param success_message [String] The success message to display if the action succeeds.
    # @param error_message [String] The error message to display if the action fails.
    # @param auth_type [Symbol] The type of authentication to use (:authorized or :colonels, :publically). Defaults to :authorized.
    # @param allow_anonymous [Boolean] Whether to allow anonymous access. Defaults to false.
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
    #   process_action(V2::Logic::GenerateAPIToken, "API Token generated successfully.", "API Token could not be generated.") do |logic|
    #     json_success(custid: cust.custid, apitoken: logic.apitoken)
    #   end
    #
    def process_action(logic_class, success_message, error_message, auth_type: :authorized, allow_anonymous: false)
      auth_method = auth_type == :colonels ? method(:colonels) : method(:authorized)

      auth_method.call(allow_anonymous) do
        logic = logic_class.new(sess, cust, req.params, locale)

        logic.domain_strategy = req.env['onetime.domain_strategy'] # never nil
        logic.display_domain = req.env['onetime.display_domain'] # can be nil

        logic.raise_concerns
        logic.process

        OT.ld <<~DEBUG
          [process_action]
            class:     #{logic_class}
            success:   #{logic.greenlighted}
            strategy:  #{logic.domain_strategy}
            display:   #{logic.display_domain}
        DEBUG

        if logic.greenlighted
          json_success(custid: cust.custid, **logic.success_data)
        else
          # Add a fresh shrimp to allow continuing without refreshing the page
          error_response(error_message, shrimp: sess.add_shrimp)
        end
      end
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

    # We don't get here from a form error unless the shrimp for this
    # request was good. Pass a delicious fresh shrimp to the client
    # so they can try again with a new one (without refreshing the
    # entire page).
    def handle_form_error ex, hsh={}
      hsh[:shrimp] = sess.add_shrimp
      hsh[:message] = ex.message
      hsh[:success] = false
      res.status = 422 # Unprocessable Entity
      json hsh
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

    def not_authorized_error hsh={}
      hsh[:message] = "Not authorized"
      res.status = 403
      json hsh
    end

    def error_response msg, hsh={}
      hsh[:message] = msg
      hsh[:success] = false
      res.status = 500 # Bad Request
      json hsh
    end

    def throttle_response msg, hsh={}
      hsh[:message] = msg
      hsh[:success] = false
      res.status = 429 # Too Many Requests
      json hsh
    end

  end
end
