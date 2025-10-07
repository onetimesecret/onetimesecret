# frozen_string_literal: true

# ErrorHandling middleware for Web Core application.
#
# Since Web Core serves Vue.js SPA entry points and all data comes from the V2 API,
# error handling is simplified to serve appropriate HTML responses that allow the
# Vue app to handle errors client-side.
#
# Key responsibilities:
# - Serve Vue entry point for most errors (let Vue handle error display)
# - Handle redirects from OT::Redirect exceptions
# - Log errors appropriately
# - Track errors in Sentry when diagnostics are enabled

module Core
  module Middleware
    class ErrorHandling
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      rescue OT::Redirect => ex
        handle_redirect(env, ex)
      rescue OT::Unauthorized => ex
        handle_unauthorized(env, ex)
      rescue StandardError => ex
        handle_error(env, ex)
      end

      private

      def handle_redirect(env, ex)
        req = Rack::Request.new(env)

        # Prevent infinite redirect loops
        if req.get? && ex.location.to_s == req.path
          OT.le "[middleware] ErrorHandling: Redirect loop detected: #{req.path} -> #{ex.location}"
          ex.instance_variable_set(:@location, '/500')
        end

        OT.info "[middleware] ErrorHandling: Redirecting to #{ex.location} (#{ex.status})"
        [ex.status, { 'Location' => ex.location }, []]
      end

      def handle_unauthorized(env, ex)
        OT.info "[middleware] ErrorHandling: Unauthorized: #{ex.message}"

        # Serve Vue entry point - let Vue show login prompt
        serve_vue_entry_point(env, status: 401)
      end

      def handle_error(env, ex)
        req = Rack::Request.new(env)

        # Log the error
        OT.le "[middleware] ErrorHandling: #{ex.class}: #{ex.message} -- #{req.url} -- #{req.ip}"
        OT.le ex.backtrace.join("\n") if OT.debug?

        # Track in Sentry if diagnostics enabled
        capture_error(ex, env) if OT.d9s_enabled

        # Serve Vue entry point - let Vue show error UI
        serve_vue_entry_point(env, status: 500)
      end

      def serve_vue_entry_point(env, status: 200)
        session = env['rack.session'] || {}
        cust = load_customer(env)
        locale = env['ots.locale'] || 'en'

        view = Core::Views::VuePoint.new(build_rack_request(env), session, cust, locale)

        [status, default_headers, [view.render]]
      end

      def load_customer(env)
        # Try Otto auth result first
        return env['otto.user'] if env['otto.user'].is_a?(Onetime::Customer)

        # Fallback to anonymous
        Onetime::Customer.anonymous
      rescue StandardError => ex
        OT.le "[middleware] ErrorHandling: Failed to load customer: #{ex.message}"
        Onetime::Customer.anonymous
      end

      def build_rack_request(env)
        @rack_request ||= {}
        @rack_request[env.object_id] ||= Rack::Request.new(env)
      end

      def default_headers
        { 'content-type' => 'text/html; charset=utf-8' }
      end

      def capture_error(error, env)
        return unless defined?(Sentry)

        Sentry.with_scope do |scope|
          if env
            req = build_rack_request(env)
            scope.set_context('request', {
              url: req.url,
              method: req.request_method,
              ip: req.ip
            })
          end

          Sentry.capture_exception(error)
        end
      rescue StandardError => ex
        OT.le "[middleware] ErrorHandling: Sentry error: #{ex.class}: #{ex.message}"
      end
    end
  end
end
