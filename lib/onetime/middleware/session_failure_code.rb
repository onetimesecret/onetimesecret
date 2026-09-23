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
    # to the JSON 401 that Otto renders when a session auth strategy refuses a
    # request (#4462).
    #
    # ## Why a middleware
    #
    # Otto builds that body inside the gem
    # (RouteAuthWrapperComponents::ResponseBuilder#json_auth_error) from the
    # failure STRING alone and offers no hook into it, so the evaluator's typed
    # reason reaches the client only as a bracket marker inside `message`.
    # Same constraint, same answer as RetryAfterHeader: the strategy stashes
    # the typed reason in the Rack env
    # (BaseSessionAuthStrategy#failure_for) and this middleware, mounted once in
    # the universal stack, carries it across the boundary.
    #
    # ## When it annotates
    #
    # All of:
    #
    # - the response is a 401 with a JSON content type and an Array body;
    # - a session strategy refused this request (the env stash is present);
    # - Otto's auth chain produced the response (its anonymous failure result
    #   carries `:auth_failure` metadata). A 401 raised later by a handler on a
    #   route that fell through to `noauth` is not a session refusal;
    # - the request presented no `Authorization` header. On a
    #   `sessionauth,basicauth` chain a rejected API credential is a
    #   `credential`-scope failure (reserved, #4469) and stays uncoded rather
    #   than being reported as a statement about the customer session.
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
      CONTENT_TYPE   = 'content-type'
      CONTENT_LENGTH = 'content-length'
      JSON_TYPE      = %r{\Aapplication/(?:[\w.+-]+\+)?json\b}i

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)
        return [status, headers, body] unless annotate?(env, status, headers, body)

        annotated = annotate(body, Onetime::SessionFailureCode.for(env[ENV_KEY]))
        return [status, headers, body] unless annotated

        set_header(headers, CONTENT_LENGTH, annotated.bytesize.to_s)
        [status, headers, [annotated]]
      end

      private

      def annotate?(env, status, headers, body)
        status.to_i == STATUS &&
          env[ENV_KEY] &&
          env['HTTP_AUTHORIZATION'].to_s.empty? &&
          otto_auth_failure?(env) &&
          headers.respond_to?(:each_pair) &&
          JSON_TYPE.match?(header(headers, CONTENT_TYPE).to_s) &&
          body.respond_to?(:to_ary)
      end

      def otto_auth_failure?(env)
        result = env['otto.strategy_result']
        return false unless result.respond_to?(:metadata)

        metadata = result.metadata
        metadata.is_a?(Hash) && metadata.key?(:auth_failure)
      end

      # @return [String, nil] the re-serialized body, or nil to leave the
      #   response untouched.
      def annotate(body, codes)
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
