# apps/web/auth/param_encoding.rb
#
# frozen_string_literal: true

require 'json'

module Auth
  # Refuse a Rodauth request whose parameters carry a String that is not valid
  # in its own encoding (SEC-B01, SEC-B08).
  #
  # WHY: Rack::UTF8Sanitizer does not reach every body. It returns early for a
  # declared non-UTF-8 charset (`application/json; charset=iso-8859-1`) and
  # skips media types outside its list (`application/vnd.api+json`, which
  # Rodauth's JSON check and Roda's json_parser both accept), and it can be
  # switched off (MIDDLEWARE_UTF8_SANITIZER=false). Both JSON parsers in the
  # stack (Oj in Rack::Parser, the json gem in Roda's json_parser) then hand
  # back a UTF-8-tagged String with invalid bytes, and the first `strip`,
  # `split` or normalization on it raises ArgumentError. On the login-request
  # routes the params read after the account lookup (the email locale, the
  # invite token) were only touched for an existing, eligible account, so the
  # 500 told an account from a missing login (config/overrides/
  # login_request_enumeration.rb).
  #
  # WHAT: one 400 with one body for any such request, whatever the route,
  # account or declared charset, before any route hook and any account lookup.
  # A request whose Strings are all valid is untouched.
  #
  # WHERE: the last step of before_rodauth (config/hooks/restrict_to.rb, the
  # sole owner of that hook), AFTER the host gates (refuse_unavailable_domain!,
  # SigninEnabled, SignupEnabled, RestrictTo, SigninGate). On a host that
  # gates a route away, the gate's 404 must stand whatever the params hold:
  # "A restricted-away method rejects as 404, matching Rodauth's behavior for
  # a feature that was never loaded" (ADR-034, reject-as-not-found-not-
  # forbidden). Run any earlier (it used to run first in around_rodauth) and
  # a bad param answered 400 on a gated route where an undefined path answers
  # 404, telling "installed but gated here" from "not installed" (SEC-B11);
  # reading the params also let Roda's json_parser answer its own 400 for a
  # malformed body. before_rodauth still runs before every route block and
  # route hook (the email-login limiter included), so before any account
  # lookup. Rodauth's json feature runs its own checks (Accept, POST-only,
  # JSON-only) ahead of this block, but they read headers, never params.
  #
  # Not covered: the OmniAuth request and callback phases (rodauth-omniauth
  # serves them from route_omniauth!, which never calls before_rodauth or
  # around_rodauth; their params are the IdP's: SAMLResponse, RelayState,
  # state), and the hand-rolled Roda routes under routes/, which read their
  # own JSON body (routes/json_body.rb).
  #
  # Internal requests are skipped: their params are the app's own, passed in
  # Ruby rather than parsed from a request (Rodauth's internal_request).
  module ParamEncoding
    # One answer for every refused request (the ADR-013 error shape).
    BAD_REQUEST_BODY = { error: 'Bad Request', error_type: 'BadRequest' }.freeze

    extend self

    # Whether a parsed param value holds a String with invalid encoding,
    # anywhere: hash keys and values, array elements, nested. A binary
    # (ASCII-8BIT) String is always valid; Symbols and other values are not
    # Strings and pass. Depth is already bounded by the parsers (Rack's param
    # depth limit, the JSON nesting limits).
    #
    # @param value [Object] a request param value, or the params Hash
    # @return [Boolean]
    def invalid?(value)
      case value
      when String then !value.valid_encoding?
      when Hash then value.any? { |key, item| invalid?(key) || invalid?(item) }
      when Array then value.any? { |item| invalid?(item) }
      else false
      end
    end

    # Halt with the 400 when the request's query or body params hold an
    # invalid String. Logs the route only, never the offending value.
    #
    # The answer is written to the Roda response and finished by a bare
    # `halt`, the way Rodauth returns its own JSON errors (return_response),
    # so it carries the router's default headers (cache-control: private,
    # no-store) like every other /auth JSON answer. A rack array passed to
    # `halt` would skip them.
    #
    # @param rodauth [Rodauth::Auth]
    # @return [void]
    def refuse_invalid!(rodauth)
      return if rodauth.send(:internal_request?)

      request = rodauth.request
      return unless invalid?(request.GET) || invalid?(request.POST)

      Auth::Logging.log_auth_event(
        :invalid_param_encoding,
        level: :info,
        current_route: rodauth.current_route,
      )
      response                 = rodauth.response
      response.status          = 400
      response['content-type'] = 'application/json'
      response.write(JSON.generate(BAD_REQUEST_BODY))
      request.halt
    end
  end
end
