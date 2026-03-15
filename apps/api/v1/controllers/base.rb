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

          # Returns 404 (not 401) when auth is disabled — intentional for
          # backwards compatibility but can mask config issues. See #2620.
          return disabled_response(req.path) unless session_auth_enforced?

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

    # V1 rate limiting [#2621]
    #
    # v0.23.x had rate limiting in the web layer; V1 reconstitution omitted
    # it. This adds basic per-IP rate limiting for secret creation endpoints
    # using Redis counters with a 20-minute fixed window, matching v0.23.x
    # behavior. Rate limits are now enforced externally (infrastructure
    # layer), so this is vestigial — preserved for V1 API contract only.
    #
    # Counts sourced from rel/0.23 etc/defaults/config.defaults.yaml:
    #   create_secret: 1000, show_secret: 1000 (per 20-min window)
    #
    # Paid-plan exemptions: authenticated users with a non-anonymous plan
    # bypass rate limits, matching v0.23.x behavior.
    V1_RATE_LIMIT_WINDOW = 1200  # 20 minutes in seconds
    V1_RATE_LIMIT_MAX_CREATES = 1000 # v0.23: limits.create_secret
    V1_RATE_LIMIT_MAX_READS = 1000   # v0.23: limits.show_secret

    # Lua script for atomic INCR + EXPIRE (prevents race condition
    # where a crash between the two commands leaves a permanent key).
    V1_RATE_LIMIT_LUA = <<~LUA.freeze
      local c = redis.call('INCR', KEYS[1])
      if tonumber(c) == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
      return c
    LUA

    def check_rate_limit!(event, max_count)
      # Paid-plan exemption: skip rate limiting for authenticated paid users
      return if cust && !cust.anonymous? && cust.planid.to_s != 'anonymous'

      ip = req.client_ipaddress.to_s
      return if ip.empty?

      key = "v1:ratelimit:#{event}:#{ip}"
      begin
        # Atomic INCR + EXPIRE via Lua script to prevent race condition.
        # Without atomicity, a crash between INCR and EXPIRE could leave
        # a permanent key that never expires, causing permanent IP blocking.
        count = Familia.redis.eval(
          V1_RATE_LIMIT_LUA, keys: [key], argv: [V1_RATE_LIMIT_WINDOW]
        )

        if count > max_count
          error_response "Rate limit exceeded. Please try again later."
          return :limited
        end
      rescue StandardError => e
        # Fail open: if Redis is down, don't block the request
        OT.le "[V1 rate_limit] #{e.class}: #{e.message}"
      end

      nil
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

    # Return a 404 when a route matched but the key param is
    # structurally invalid (too short to be a real identifier).
    # Uses V1's standard not_found_response for a consistent
    # error shape across all V1 endpoints.
    def otto_not_found
      not_found_response 'Not Found'
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
