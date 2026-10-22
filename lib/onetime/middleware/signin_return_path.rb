# lib/onetime/middleware/signin_return_path.rb
#
# frozen_string_literal: true

require 'rack/request'
require 'rack/utils'
require_relative '../utils'

module Onetime
  module Middleware
    ##
    # SigninReturnPath
    #
    # Adds the page a signed-out visitor asked for to the sign-in redirect
    # Otto answers with, as `/signin?redirect=<path>`, so the app brings the
    # visitor back to that page once they have signed in.
    #
    # ## Why a middleware
    #
    # A web route with auth=sessionauth (GET /recent, /dashboard, /account
    # and the rest) requested by a signed-out browser is refused by Otto's
    # auth chain, and Otto renders the refusal inside the gem
    # (RouteAuthWrapperComponents::ResponseBuilder#html_auth_error): a 302 to
    # the fixed login_path, '/signin', with no hook for the request path. The
    # app's own router guard sends the same routes to
    # `{ path: '/signin', query: { redirect: from.fullPath } }` on a
    # client-side navigation (src/router/guards.routes.ts, redirectToSignIn),
    # and the sign-in flow consumes that query (usePostAuthRedirect). A full
    # page load, which is what a link in an email is, got the bare 302 and
    # lost the destination. Same constraint, same answer as
    # SessionFailureCode: the refusal is rewritten on the way out.
    #
    # ## When it rewrites
    #
    # All of:
    #
    # - a GET or HEAD request. The return path is a page to come back to; a
    #   POST's path is not one;
    # - Otto's auth chain refused the request: env['otto.strategy_result'] is
    #   the anonymous result the chain leaves on a refusal, whose metadata
    #   has the :auth_failure key. An app's own redirect to the sign-in page (the
    #   sign-out handler, a completed registration) runs after the chain
    #   admitted the request and is left alone;
    # - the response is a 302 whose location is exactly SIGNIN_PATH, with no
    #   query of its own;
    # - the request's full path (script name, path, query string) passes
    #   OT::Utils.safe_internal_path?, the validator the app mirrors in
    #   isValidInternalPath. Anything else keeps the bare redirect.
    #
    # The value is percent-encoded as a query parameter. The app decodes it
    # once, validates it again, and only then navigates to it. Nothing here
    # widens access: the page behind the redirect still needs a session.
    #
    class SigninReturnPath
      # Otto's default login_path (ResponseBuilder#html_auth_error); the app
      # sets no other.
      SIGNIN_PATH = '/signin'

      # The query parameter the router guard writes and the sign-in flow reads.
      REDIRECT_PARAM = 'redirect'

      STATUS   = 302
      METHODS  = %w[GET HEAD].freeze
      LOCATION = 'location'

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)
        return [status, headers, body] unless rewrite?(env, status, headers)

        return_path = Rack::Request.new(env).fullpath
        return [status, headers, body] unless Onetime::Utils.safe_internal_path?(return_path)

        set_header(headers, LOCATION, "#{SIGNIN_PATH}?#{REDIRECT_PARAM}=#{Rack::Utils.escape(return_path)}")
        [status, headers, body]
      end

      private

      def rewrite?(env, status, headers)
        status.to_i == STATUS &&
          METHODS.include?(env['REQUEST_METHOD']) &&
          refused_by_auth_chain?(env) &&
          headers.respond_to?(:each_pair) &&
          header(headers, LOCATION) == SIGNIN_PATH
      end

      # Otto's RouteAuthWrapper sets env['otto.strategy_result'] to an
      # anonymous result with :auth_failure metadata when every strategy
      # failed (handle_all_strategies_failed), and to the admitting result
      # otherwise. Routes without an auth requirement get an anonymous
      # result without that key.
      def refused_by_auth_chain?(env)
        result = env['otto.strategy_result']
        return false unless result.respond_to?(:metadata)

        metadata = result.metadata
        metadata.is_a?(Hash) && metadata.key?(:auth_failure)
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
