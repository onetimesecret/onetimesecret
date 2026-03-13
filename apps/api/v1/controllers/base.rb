# apps/api/v1/controllers/base.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module V1

  module ControllerBase
    include V1::ControllerHelpers

    attr_reader :req, :res
    attr_reader :cust, :locale, :sess

    def initialize req, res
      @req, @res = req, res
    end

    # Access the current session via Rack::Request extension
    # Required by SessionHelpers module
    def session
      req.session
    end

    # Alias for req to support SessionHelpers
    # Required by SessionHelpers#authenticate! which calls request.session_options
    def request
      req
    end

    def publically
      carefully do
        check_locale!
        yield
      end
    end

    # Authorize API v1 requests using Basic Auth or anonymous access only.
    #
    # Session/cookie authentication is NOT supported for API v1 routes.
    # This eliminates CSRF attack vectors - the Rack::Protection middleware
    # handles CSRF for web routes, while API routes use API keys.
    #
    # @example Basic Auth
    #   curl -F 'ttl=7200' -u 'EMAIL:APITOKEN' http://HOST:3000/api/v1/generate
    #
    # @param allow_anonymous [Boolean] Whether to allow unauthenticated requests
    def authorized(allow_anonymous = false)
      carefully(nil, 'application/json', app: :api) do
        check_locale!

        req.env['otto.auth'] ||= Rack::Auth::Basic::Request.new(req.env)
        auth = req.env['otto.auth']

        if auth.provided?
          # Basic Auth path
          # Use identical error messages to prevent user enumeration
          raise OT::Unauthorized, 'Invalid credentials' unless auth.basic?

          custid, apitoken = *(auth.credentials || [])
          raise OT::Unauthorized, 'Invalid credentials' if custid.to_s.empty? || apitoken.to_s.empty?

          return disabled_response(req.path) unless authentication_enabled?

          OT.ld "[authorized] Attempt for '#{custid}' via #{req.client_ipaddress} (basic auth)"
          possible = Onetime::Customer.load_by_extid_or_email(custid)

          @cust = possible if possible&.apitoken?(apitoken)
          raise OT::Unauthorized, 'Invalid credentials' if cust.nil?

          OT.ld "[authorized] '#{custid}' via #{req.client_ipaddress} (basic auth authenticated)"

        elsif allow_anonymous
          # Anonymous path - only for routes that explicitly opt-in
          @cust = Onetime::Customer.anonymous

          if OT.debug?
            ip_address = req.client_ipaddress.to_s
            OT.ld "[authorized] Anonymous request via #{ip_address}"
          end

        else
          # No credentials and anonymous not allowed
          raise OT::Unauthorized, 'Invalid credentials'
        end

        raise OT::Unauthorized, 'Invalid credentials' if cust.nil?

        yield
      end
    end

    def json hsh
      res.headers['content-type'] = "application/json; charset=utf-8"
      res.body = hsh.to_json
    end

    def handle_form_error(ex, hsh = {})
      hsh ||= {}
      error_response ex.message, hsh
    end

    def secret_not_found_response
      not_found_response "Unknown secret", :secret_key => req.params['key']
    end

    # Minimum length for a valid secret/receipt identifier. V0.23 keys
    # were 31 chars (base36), v0.24 keys are 62 chars (VerifiableIdentifier).
    # Any key shorter than this cannot be a real identifier — it's likely
    # a sub-path segment (e.g. "burn") that reached a :key route after
    # Rack::Protection::PathTraversal collapsed double slashes.
    V1_MIN_IDENTIFIER_LENGTH = 20

    # Returns true when the key param is structurally valid as an
    # identifier (meets minimum length). Short strings like "burn"
    # or "recent" fail this check, matching v0.23 behavior where
    # such paths returned Otto's default 404.
    def valid_identifier?(key)
      key.to_s.length >= V1_MIN_IDENTIFIER_LENGTH
    end

    # Return the same response format as Otto's not_found handler.
    # Used when a route matched but the key param is structurally
    # invalid — reproduces v0.23 behavior where these paths never
    # matched a route at all.
    def otto_not_found
      res.status = 404
      json :error => 'Not Found'
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
