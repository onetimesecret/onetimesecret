# apps/web/core/middleware/error_handling.rb
#
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
      include Onetime::LoggerMethods

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
          http_logger.error 'Redirect loop detected',
            {
              exception: ex,
              path: req.path,
              target: ex.location,
            }
          ex.instance_variable_set(:@location, '/500')
        end

        http_logger.info 'Redirecting',
          {
            location: ex.location,
            status: ex.status,
          }
        [ex.status, { 'location' => ex.location }, []]
      end

      def handle_unauthorized(env, ex)
        req = Rack::Request.new(env)
        http_logger.info 'Unauthorized access',
          {
            exception: ex,
            url: req.url,
            ip: req.ip,
          }

        # Serve Vue entry point - let Vue show login prompt
        serve_vue_entry_point(env, status: 401)
      end

      def handle_error(env, ex)
        req = Rack::Request.new(env)

        # Log the error with structured context
        http_logger.error 'Request processing failed',
          {
            exception: ex,
            url: req.url,
            method: req.request_method,
            ip: req.ip,
            backtrace: ex.backtrace&.first(20),
          }

        # Track in Sentry if diagnostics enabled
        http_logger.debug '[sentry] handle_error → capture decision',
          {
            exception_class: ex.class.name,
            d9s_enabled: OT.d9s_enabled,
            sentry_defined: defined?(Sentry) ? true : false,
            sentry_initialized: (defined?(Sentry) && Sentry.initialized?) || false,
            request_id: env['HTTP_X_REQUEST_ID'],
          }
        if OT.d9s_enabled
          capture_error(ex, env)
        else
          http_logger.debug '[sentry] skipping capture — d9s_enabled=false',
            {
              request_id: env['HTTP_X_REQUEST_ID'],
            }
        end

        # Serve Vue entry point - let Vue show error UI
        serve_vue_entry_point(env, status: 500)
      end

      def serve_vue_entry_point(env, status: 200)
        req = build_rack_request(env)

        # Debug template path configuration
        http_logger.debug 'Template debug info',
          {
            rhales_frozen: Rhales.configuration.frozen?,
            template_paths: Rhales.configuration.template_paths,
            current_dir: Dir.pwd,
            template_exists: File.exist?(File.join(Dir.pwd, 'apps', 'web', 'core', 'templates', 'index.rue')),
          }

        # Simplified: BaseView now extracts everything from req
        view = Core::Views::VuePoint.new(req)

        [status, default_headers, [view.render]]
      end

      def build_rack_request(env)
        @rack_request                ||= {}
        @rack_request[env.object_id] ||= Rack::Request.new(env)
      end

      def default_headers
        { 'content-type' => 'text/html; charset=utf-8' }
      end

      def capture_error(error, env)
        unless defined?(Sentry)
          http_logger.debug '[sentry] capture_error aborted — Sentry constant not defined',
            {
              request_id: env && env['HTTP_X_REQUEST_ID'],
            }
          return
        end

        http_logger.debug '[sentry] capture_error → entering Sentry.with_scope',
          {
            exception_class: error.class.name,
            exception_message: error.message,
            sentry_initialized: Sentry.initialized?,
            request_id: env && env['HTTP_X_REQUEST_ID'],
          }

        event_id = nil
        Sentry.with_scope do |scope|
          if env
            req = build_rack_request(env)
            scope.set_context(
              'request',
              {
                url: req.url,
                method: req.request_method,
                ip: req.ip,
              },
            )
          end

          event_id = Sentry.capture_exception(error)
        end

        http_logger.debug '[sentry] capture_error returned',
          {
            event_id: event_id,
            exception_class: error.class.name,
            request_id: env && env['HTTP_X_REQUEST_ID'],
          }
      rescue StandardError => ex
        http_logger.error 'Sentry capture failed',
          {
            exception: ex,
          }
      end
    end
  end
end
