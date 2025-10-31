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
      include Onetime::Logging

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
          http_logger.error "Redirect loop detected",
            exception: ex,
            path: req.path,
            target: ex.location
          ex.instance_variable_set(:@location, '/500')
        end

        http_logger.info "Redirecting",
          location: ex.location,
          status: ex.status
        [ex.status, { 'location' => ex.location }, []]
      end

      def handle_unauthorized(env, ex)
        req = Rack::Request.new(env)
        http_logger.info "Unauthorized access",
          exception: ex,
          url: req.url,
          ip: req.ip

        # Serve Vue entry point - let Vue show login prompt
        serve_vue_entry_point(env, status: 401)
      end

      def handle_error(env, ex)
        req = Rack::Request.new(env)

        # Log the error with structured context
        http_logger.error "Request processing failed",
          exception: ex,
          url: req.url,
          method: req.request_method,
          ip: req.ip,
          backtrace: ex.backtrace&.first(20)

        # Track in Sentry if diagnostics enabled
        capture_error(ex, env) if OT.d9s_enabled

        # Serve Vue entry point - let Vue show error UI
        serve_vue_entry_point(env, status: 500)
      end

      def serve_vue_entry_point(env, status: 200)
        req = build_rack_request(env)
        session = req.session
        cust = load_customer(req)
        locale = req.locale

        view = Core::Views::VuePoint.new(req, session, cust, locale)

        [status, default_headers, [view.render]]
      end

      def load_customer(req)
        # Use Rack::Request extension method
        user = req.user
        return user if user&.is_a?(Onetime::Customer)

        # Fallback to anonymous
        Onetime::Customer.anonymous
      rescue StandardError => ex
        http_logger.error "Failed to load customer",
          exception: ex
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
        http_logger.error "Sentry capture failed",
          exception: ex
      end
    end
  end
end
