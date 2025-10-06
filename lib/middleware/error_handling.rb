# frozen_string_literal: true

# ErrorHandling middleware provides centralized exception handling for the Web Core application.
# It replaces the controller-level `carefully` wrapper method with proper middleware architecture.
#
# Handles all Onetime-specific exceptions plus standard Ruby errors, providing appropriate
# HTTP responses, Sentry integration, form field preservation, and customer activity logging.
#
# This middleware should be placed early in the middleware stack, after session middleware
# but before the router, to catch all exceptions from downstream components.
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
    rescue OT::FormError => ex
      handle_form_error(env, ex)
    rescue OT::MissingSecret => ex
      handle_missing_secret(env, ex)
    rescue OT::RecordNotFound => ex
      handle_record_not_found(env, ex)
    rescue Familia::NotDistinguishableError => ex
      handle_familia_type_error(env, ex)
    rescue Familia::NotConnected, Familia::Problem => ex
      handle_familia_error(env, ex)
    rescue Errno::ECONNREFUSED => ex
      handle_connection_refused(env, ex)
    rescue StandardError => ex
      handle_standard_error(env, ex)
    ensure
      log_customer_activity(env) if env['rack.session']
    end

    private

    def handle_redirect(env, ex)
      req = Rack::Request.new(env)

      # Prevent infinite redirect loops
      if req.get? && ex.location.to_s == req.path
        OT.le "[error_handling] Redirect loop detected: #{req.path} -> #{ex.location}"
        ex.instance_variable_set(:@location, '/500')
      end

      OT.info "[error_handling] Redirecting to #{ex.location} (#{ex.status})"
      [ex.status, { 'Location' => ex.location }, []]
    end

    def handle_unauthorized(env, ex)
      OT.info "[error_handling] Unauthorized: #{ex.message}"

      session = env['rack.session']
      cust = load_customer(env)
      locale = env['ots.locale'] || 'en'

      view = Core::Views::Error.new(build_rack_request(env), session, cust, locale)
      view.add_error('Not authorized')

      [401, default_headers, [view.render]]
    end

    def handle_form_error(env, ex)
      req = Rack::Request.new(env)
      session = env['rack.session']

      OT.ld "[error_handling] FormError: #{ex.message} (#{req.path})"

      # Track form errors in Sentry - they can indicate bugs
      capture_message(ex.message, :error, env)

      # Store form fields and error message in session for redirect
      session['form_fields'] = ex.form_fields if ex.form_fields
      session['error_message'] = ex.message

      # Determine redirect location
      redirect_path = req.params['redirect'] || req.env['HTTP_REFERER'] || req.path

      # Prevent infinite loops
      redirect_path = '/500' if req.get? && redirect_path == req.path

      [302, { 'Location' => redirect_path }, []]
    end

    def handle_missing_secret(env, _ex)
      cust = load_customer(env)
      session = env['rack.session']
      locale = env['ots.locale'] || 'en'

      view = Core::Views::UnknownSecret.new(build_rack_request(env), session, cust, locale)

      [404, default_headers, [view.render]]
    end

    def handle_record_not_found(env, ex)
      req = Rack::Request.new(env)
      cust = load_customer(env)
      session = env['rack.session']
      locale = env['ots.locale'] || 'en'

      OT.ld "[error_handling] RecordNotFound: #{ex.message} (#{req.path})"

      view = Core::Views::VuePoint.new(build_rack_request(env), session, cust, locale)
      view.add_error(ex.message) unless ex.message.to_s.empty?

      [404, default_headers, [view.render]]
    end

    def handle_familia_type_error(env, ex)
      req = Rack::Request.new(env)
      session = env['rack.session']
      cust = load_customer(env)
      locale = env['ots.locale'] || 'en'

      session_id = session&.id&.to_s || req.cookies['onetime.session'] || 'unknown'
      short_session_id = session_id.length <= 10 ? session_id : "#{session_id[0, 10]}..."

      obscured = cust&.anonymous? ? 'anonymous' : Onetime::Utils.obscure_email(cust&.custid)

      OT.le "[error_handling] NotDistinguishableError: #{obscured} (#{req.ip}): #{short_session_id} (#{req.url})"

      # Track attempts to save non-string data as a warning
      capture_error(ex, :warning, env)

      view = Core::Views::Error.new(build_rack_request(env), session, cust, locale)
      view.add_error("We're sorry, but we can't process your request at this time.")

      [400, default_headers, [view.render]]
    end

    def handle_familia_error(env, ex)
      req = Rack::Request.new(env)
      cust = load_customer(env)
      session = env['rack.session']
      locale = env['ots.locale'] || 'en'

      OT.le "[error_handling] #{ex.class}: #{ex.message}"
      OT.le ex.backtrace

      # Track Familia errors as regular exceptions
      capture_error(ex, :error, env)

      view = Core::Views::Error.new(build_rack_request(env), session, cust, locale)
      view.add_error('An error occurred :[')

      [500, default_headers, [view.render]]
    end

    def handle_connection_refused(env, ex)
      req = Rack::Request.new(env)
      cust = load_customer(env)
      session = env['rack.session']
      locale = env['ots.locale'] || 'en'

      OT.le "[error_handling] Connection refused: #{ex.message}"
      OT.le ex.backtrace

      # Track DB connection errors as fatal
      capture_error(ex, :fatal, env)

      view = Core::Views::Error.new(build_rack_request(env), session, cust, locale)
      view.add_error("We'll be back shortly!")

      [503, default_headers, [view.render]]
    end

    def handle_standard_error(env, ex)
      req = Rack::Request.new(env)
      session = env['rack.session']
      cust = load_customer(env)
      locale = env['ots.locale'] || 'en'

      custid = cust&.custid || '<notset>'

      OT.le "[error_handling] #{ex.class}: #{ex.message} -- #{req.url} -- #{req.ip} #{custid} #{session&.id} #{locale}"
      OT.le ex.backtrace.join("\n")

      # Track unexpected errors
      capture_error(ex, :error, env)

      view = Core::Views::Error.new(build_rack_request(env), session, cust, locale)
      view.add_error('An unexpected error occurred :[')

      [500, default_headers, [view.render]]
    end

    def load_customer(env)
      # Try Otto auth result first
      return env['otto.user'] if env['otto.user'].is_a?(Onetime::Customer)

      # Try from session
      session = env['rack.session']
      return Onetime::Customer.anonymous unless session

      identity_id = session['identity_id']
      return Onetime::Customer.anonymous unless identity_id

      Onetime::Customer.load(identity_id) || Onetime::Customer.anonymous
    rescue StandardError => ex
      OT.le "[error_handling] Failed to load customer: #{ex.message}"
      Onetime::Customer.anonymous
    end

    def build_rack_request(env)
      @rack_request ||= {}
      @rack_request[env.object_id] ||= Rack::Request.new(env)
    end

    def default_headers
      { 'content-type' => 'text/html; charset=utf-8' }
    end

    def log_customer_activity(env)
      return unless env['rack.session']
      return unless env['rack.request']

      req = build_rack_request(env)
      cust = load_customer(env)

      return if cust.nil? || cust.anonymous?

      cust.update_fields :updated => Time.now.to_i
      cust.save
    rescue StandardError => ex
      OT.le "[error_handling] Failed to log customer activity: #{ex.message}"
    end

    def capture_error(error, level = :error, env)
      return unless defined?(Sentry)

      Sentry.with_scope do |scope|
        scope.set_level(level)

        # Add request context
        if env
          req = build_rack_request(env)
          scope.set_context('request', {
            url: req.url,
            method: req.request_method,
            headers: sanitize_headers(req.env),
            params: req.params
          })
        end

        Sentry.capture_exception(error)
      end
    rescue StandardError => ex
      OT.le "[error_handling] Sentry error: #{ex.class}: #{ex.message}"
    end

    def capture_message(message, level = :log, env)
      return unless defined?(Sentry)

      Sentry.with_scope do |scope|
        scope.set_level(level)

        if env
          req = build_rack_request(env)
          scope.set_context('request', {
            url: req.url,
            method: req.request_method
          })
        end

        Sentry.capture_message(message)
      end
    rescue StandardError => ex
      OT.le "[error_handling] Sentry message error: #{ex.class}: #{ex.message}"
    end

    def sanitize_headers(env)
      headers = env.select { |k, _v| k.start_with?('HTTP_') }

      # Remove sensitive headers
      headers.delete('HTTP_AUTHORIZATION')
      headers.delete('HTTP_COOKIE')

      headers
    rescue StandardError => ex
      OT.le "[error_handling] Header sanitization error: #{ex.message}"
      {}
    end
  end
end
