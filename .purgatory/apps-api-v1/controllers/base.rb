# .purgatory/apps-api-v1/controllers/base.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module V1

  module ControllerBase
    include V1::ControllerHelpers

    attr_reader :req, :res
    attr_reader :cust, :locale
    attr_reader :ignoreshrimp, :sess

    def initialize req, res
      @req, @res = req, res
    end

    def publically
      carefully do
        check_locale!
        yield
      end
    end

    # curl -F 'ttl=7200' -u 'EMAIL:APITOKEN' http://LOCALHOSTNAME:3000/api/v1/generate
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
          possible = V1::Customer.load custid
          raise OT::Unauthorized, "No such customer" if possible.nil?

          @cust = possible if possible.apitoken?(apitoken)
          raise OT::Unauthorized, "Invalid credentials" if cust.nil? # wrong token

          # For basic auth, authenticate the session directly
          authenticate!(@cust) if respond_to?(:authenticate!)

          OT.ld "[authorized] '#{custid}' via #{req.client_ipaddress} (basic auth authenticated)"

        # Second line, check for session cookie. We allow this in certain cases
        # like API requests coming from hybrid Vue components.
        elsif req.cookie?(:sess) || session['external_id']

          setup_request_context if respond_to?(:setup_request_context)

          unless authenticated? || allow_anonymous
            raise OT::Unauthorized, "Session not authenticated"
          end

          # Customer is loaded via setup_request_context or current_customer helper
          @cust = current_customer
          @cust ||= V1::Customer.anonymous if allow_anonymous

          raise OT::Unauthorized, "Invalid credentials" if cust.nil? # wrong token

          custid = @cust.custid unless @cust.nil?
          OT.ld "[authorized] '#{custid}' via #{req.client_ipaddress} (session)"

          # Check CSRF for state-changing requests
          check_shrimp!

        # Otherwise, we have no credentials, so we must be anonymous. Only
        # methods that opt-in to allow anonymous sessions will be allowed to
        # proceed.
        else

          unless allow_anonymous
            raise OT::Unauthorized, "No session or credentials"
          end

          @cust = V1::Customer.anonymous
          # Session is already created by middleware

          if OT.debug?
            ip_address = req.client_ipaddress.to_s
            session_id = session.id&.private_id || 'unknown'
            message = "[authorized] Anonymous session via #{ip_address} (session #{session_id})"
            OT.ld message
          end

        end

        if cust.nil?
          raise OT::Unauthorized, "[bad-cust] '#{custid}' via #{req.client_ipaddress}"
        end

        yield
      end
    end

    def json hsh
      res.headers['content-type'] = "application/json; charset=utf-8"
      res.body = hsh.to_json
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
      regenerate_shrimp! if respond_to?(:regenerate_shrimp!)
      hsh[:shrimp] = shrimp_token if respond_to?(:shrimp_token)
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

  end
end
