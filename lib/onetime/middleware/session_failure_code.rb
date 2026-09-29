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
    # credential it presented (#4469).
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
    # every surface. Group D (#4469 follow-up) extends the same annotate path
    # with headers: `annotate` is the one place to add them.
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
    # - the response is a JSON 401 with an Array body, or a JSON 403 for
    #   which a credential-scope reason is stashed (Rodauth answers a
    #   locked-out or unverified account with 403). A bare 403, or a 403 on
    #   a request whose stash is a session reason, is never touched;
    # - a reason is stashed;
    # - the stash is the refusal being answered. A session reason on an Otto
    #   surface is stashed before the handler runs, so it counts only when
    #   Otto's auth chain produced the response (its anonymous failure result
    #   carries `:auth_failure` metadata); a 401 raised later by a handler on a
    #   route that fell through to `noauth` is not a session refusal. A
    #   credential reason is stashed by the code that renders the refusal, and
    #   the /auth Roda app has no Otto chain at all, so both are taken as is.
    #
    # It never overwrites a `code` already in the body, never touches another
    # status or content type, and leaves the response exactly as it found it
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
      # Annotated only for a credential-scope stash. Headers a follow-up adds
      # for the 401 challenge do not apply here: a 403 is not a challenge.
      CREDENTIAL_STATUS = 403
      CONTENT_TYPE   = 'content-type'
      CONTENT_LENGTH = 'content-length'
      JSON_TYPE      = %r{\Aapplication/(?:[\w.+-]+\+)?json\b}i

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
        env[ENV_KEY] &&
          status_annotated?(env, status) &&
          refusal_answered?(env) &&
          headers.respond_to?(:each_pair) &&
          JSON_TYPE.match?(header(headers, CONTENT_TYPE).to_s) &&
          body.respond_to?(:to_ary)
      end

      def status_annotated?(env, status)
        return true if status.to_i == STATUS

        status.to_i == CREDENTIAL_STATUS && Onetime::SessionFailureCode.credential?(env[ENV_KEY])
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

      # The one place the refusal is rendered onto the response. Returns the
      # response untouched when the body cannot carry the pair.
      def annotate(env, status, headers, body)
        codes     = Onetime::SessionFailureCode.for(env[ENV_KEY])
        annotated = annotate_body(body, codes)
        return [status, headers, body] unless annotated

        set_header(headers, CONTENT_LENGTH, annotated.bytesize.to_s)
        [status, headers, [annotated]]
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

      def header_key(headers, name)
        headers.each_pair { |key, _value| return key if key.to_s.casecmp(name).zero? }
        nil
      end
    end
  end
end
