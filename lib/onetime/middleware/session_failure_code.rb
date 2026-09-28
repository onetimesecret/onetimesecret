# lib/onetime/middleware/session_failure_code.rb
#
# frozen_string_literal: true

require 'json'
require_relative '../session/failure_code'

module Onetime
  module Middleware
    ##
    # SessionFailureCode
    #
    # Adds the stable `code` / `code_scope` pair (Onetime::SessionFailureCode)
    # to a JSON 401 that refused a request for its session (#4462) or for a
    # credential it presented (#4469), and gives the refusal its HTTP
    # semantics: a `WWW-Authenticate` challenge on every annotated 401, and a
    # 503 with `Retry-After` in place of the 401 when the session could not be
    # verified at all (#4469 follow-up, v0.27).
    #
    # ## Why a middleware
    #
    # Otto builds the session 401 inside the gem
    # (RouteAuthWrapperComponents::ResponseBuilder#json_auth_error) from the
    # failure STRING alone and offers no hook into it, so the evaluator's typed
    # reason reaches the client only as a bracket marker inside `message`.
    # Rodauth likewise renders its own JSON error and exposes the reason only
    # through `set_error_reason`. Same constraint, same answer as
    # RetryAfterHeader: the code that refuses stashes the typed reason in the
    # Rack env (Onetime::SessionFailureCode.stash) and this middleware,
    # mounted once in the universal stack, carries it across the boundary for
    # every surface. `annotate` is the one place the refusal is rendered, so
    # the status and the headers are decided there as well as the body.
    #
    # ## The challenge
    #
    # RFC 9110 §15.5.2 requires a 401 to carry a `WWW-Authenticate` header
    # with at least one challenge applicable to the target resource. Otto's
    # `json_auth_error` and the /auth Roda app send none. The scheme depends
    # on which credential the refusal is about, never on the route's own
    # chain, because a browser opens its native credentials dialog on any
    # same-origin fetch response that carries a `Basic` challenge:
    #
    # - `Session` (SESSION_CHALLENGE), a scheme token of this application, for
    #   a refused or unverifiable cookie session and for a rejected login,
    #   second factor or password confirmation. There is no registered HTTP
    #   scheme for a cookie session and no browser acts on an unknown one, so
    #   the header satisfies the RFC without a dialog. It is the challenge on
    #   the routes the browser client calls, including a `sessionauth,
    #   basicauth` route refused for its session, where the header the route
    #   would also accept was never examined.
    # - `Basic` (BASIC_CHALLENGE) only when a Basic auth strategy rejected an
    #   `Authorization` header (`api_key_invalid`, or `suspended_credentials`
    #   on a request that presented one). Basic is the applicable scheme for
    #   that resource (RFC 7617), and the client already chose it by sending
    #   the header; the browser client never does.
    #
    # A `WWW-Authenticate` an app already set is kept.
    #
    # ## The 503
    #
    # A refusal in the `verification_unavailable` scope is not a verdict on
    # the session: the datastore that would verify it could not be reached.
    # RFC 9110 §15.6.4's 503 ("temporary overload ... likely to be alleviated
    # after some delay") describes that, 401 does not, so the status is
    # rewritten to 503 with `Retry-After: UNAVAILABLE_RETRY_AFTER` (§10.2.3,
    # delay-seconds, the value `GET /bootstrap/me` uses for its own 503). The body keeps
    # every field the 401 had plus the pair, so a client tells this 503 from
    # any other by `code_scope`. The header is set here rather than through
    # RetryAfterHeader's env stash so this middleware needs no particular
    # position relative to that one; a `Retry-After` an app already set is
    # kept. No other scope changes status.
    #
    # ## Who stashes
    #
    # - BaseSessionAuthStrategy#failure_for: the evaluator reason, BEFORE
    #   Otto's chain has resolved. Authoritative only if the chain then
    #   refuses the request (see "When it annotates").
    # - Helpers#credentialed_failure, for the Basic auth strategies: a
    #   credential reason, only on the TERMINAL failure that fails the chain
    #   closed. A rejected header a valid session outranks stashes nothing.
    # - Auth::Router, before r.rodauth, for a request with no session: the
    #   anonymous reason, so a login-required refusal from Rodauth or from a
    #   custom /auth route is coded the same way the Otto surfaces code it.
    # - Auth::CredentialFailureCode, from Rodauth's `set_error_reason`: a
    #   credential reason replaces the router's stash for a rejected login or
    #   password confirmation; any other Rodauth error withdraws it.
    # - The /auth re-authentication and SSO-linking routes and the simple-mode
    #   sign-in controller: a credential reason, written as they answer.
    #
    # ## When it annotates
    #
    # All of:
    #
    # - the response is a 401 with a JSON content type and an Array body;
    # - a reason is stashed;
    # - the stash is the refusal being answered. A session reason on an Otto
    #   surface is stashed before the handler runs, so it counts only when
    #   Otto's auth chain produced the response (its anonymous failure result
    #   carries `:auth_failure` metadata); a 401 raised later by a handler on a
    #   route that fell through to `noauth` is not a session refusal. A
    #   credential reason is stashed by the code that renders the refusal, and
    #   the /auth Roda app has no Otto chain at all, so both are taken as is.
    #
    # It never overwrites a `code` already in the body, never touches a
    # response whose status is not 401 or whose content type is not JSON, and
    # leaves the response exactly as it found it (status, headers and body)
    # when the body is not a JSON object. An uncoded 401 is always a safe
    # outcome: clients treat it as making no statement about the session.
    #
    # `content-length` is recomputed because Otto sets it from the original
    # body and Rack::ContentLength (mounted outside this middleware) does not
    # replace a value that is already present.
    #
    class SessionFailureCode
      ENV_KEY = Onetime::SessionFailureCode::ENV_KEY

      STATUS         = 401
      CONTENT_TYPE   = 'content-type'
      CONTENT_LENGTH = 'content-length'
      JSON_TYPE      = %r{\Aapplication/(?:[\w.+-]+\+)?json\b}i

      # Rack 3 requires lowercase response header names.
      WWW_AUTHENTICATE = 'www-authenticate'
      RETRY_AFTER      = 'retry-after'
      AUTHORIZATION    = 'HTTP_AUTHORIZATION'

      # The realm names the scope of protection (RFC 9110 §11.4). One fixed
      # value: the challenge is read by machines, and a per-host value would
      # have to be quoted from the request.
      REALM             = 'onetimesecret'
      SESSION_CHALLENGE = %(Session realm="#{REALM}")
      BASIC_CHALLENGE   = %(Basic realm="#{REALM}")

      # The status a `verification_unavailable` refusal answers, and its
      # Retry-After in seconds.
      UNAVAILABLE_STATUS      = 503
      UNAVAILABLE_RETRY_AFTER = 5

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)
        return [status, headers, body] unless annotate?(env, status, headers, body)

        annotate(env, status, headers, body)
      end

      private

      def annotate?(env, status, headers, body)
        status.to_i == STATUS &&
          env[ENV_KEY] &&
          refusal_answered?(env) &&
          headers.respond_to?(:each_pair) &&
          JSON_TYPE.match?(header(headers, CONTENT_TYPE).to_s) &&
          body.respond_to?(:to_ary)
      end

      # Whether the stashed reason is the refusal this response answers.
      def refusal_answered?(env)
        return true if Onetime::SessionFailureCode.credential?(env[ENV_KEY])

        result = env['otto.strategy_result']
        # No Otto auth chain ran: the /auth Roda app, whose router and routes
        # stash only as they refuse.
        return true unless result.respond_to?(:metadata)

        metadata = result.metadata
        metadata.is_a?(Hash) && metadata.key?(:auth_failure)
      end

      # The one place the refusal is rendered onto the response: the pair in
      # the body, the challenge, and for an outage the 503 and its
      # Retry-After. Returns the response untouched when the body cannot
      # carry the pair, so a response never gets the headers without the
      # code that explains them.
      def annotate(env, status, headers, body)
        reason    = env[ENV_KEY]
        codes     = Onetime::SessionFailureCode.for(reason)
        annotated = annotate_body(body, codes)
        return [status, headers, body] unless annotated

        set_header(headers, CONTENT_LENGTH, annotated.bytesize.to_s)

        if codes['code_scope'] == Onetime::SessionFailureCode::SCOPE_VERIFICATION_UNAVAILABLE
          set_header_unless_present(headers, RETRY_AFTER, UNAVAILABLE_RETRY_AFTER.to_s)
          return [UNAVAILABLE_STATUS, headers, [annotated]]
        end

        set_header_unless_present(headers, WWW_AUTHENTICATE, challenge(env, reason))
        [status, headers, [annotated]]
      end

      # See "The challenge" above. `api_key_invalid` is stashed only by the
      # Basic auth strategies; `suspended_credentials` is stashed by them and
      # by the simple-mode sign-in, and only the strategies examine an
      # `Authorization` header, so its presence tells the two apart.
      def challenge(env, reason)
        reason = reason.to_sym
        basic  = reason == :api_key_invalid ||
                 (reason == :suspended_credentials && !env[AUTHORIZATION].to_s.empty?)
        basic ? BASIC_CHALLENGE : SESSION_CHALLENGE
      end

      # @return [String, nil] the re-serialized body, or nil to leave the
      #   response untouched.
      def annotate_body(body, codes)
        return nil if codes.empty?

        parsed = JSON.parse(body.to_ary.join)
        return nil unless parsed.is_a?(Hash)
        return nil if parsed.key?('code')

        JSON.generate(parsed.merge(codes))
      rescue JSON::ParserError
        nil
      end

      # Case-insensitive read/write: Otto's error path returns a plain Hash
      # with lowercase keys, other apps may hand back Rack::Headers.
      def header(headers, name)
        key = header_key(headers, name)
        key && headers[key]
      end

      def set_header(headers, name, value)
        headers[header_key(headers, name) || name] = value
      end

      def set_header_unless_present(headers, name, value)
        headers[name] = value unless header_key(headers, name)
      end

      def header_key(headers, name)
        headers.each_pair { |key, _value| return key if key.to_s.casecmp(name).zero? }
        nil
      end
    end
  end
end
