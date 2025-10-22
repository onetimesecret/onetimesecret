# lib/middleware/session_debugger.rb
#
# Lightweight debugging middleware for session persistence issues
#
# Enable with:
#   DEBUG_SESSION=true bundle exec puma
#
# This middleware logs critical session information at key points to help
# diagnose authentication persistence problems:
# - Session ID continuity across requests
# - Cookie headers (Set-Cookie and Cookie)
# - Session data before and after request processing
# - Redis storage verification
#
require 'oj'
require_relative 'logging'

module Rack
  class SessionDebugger
    include Middleware::Logging

    def initialize(app)
      @app     = app
      @enabled = ENV['DEBUG_SESSION'].to_s.match?(/^(true|1|yes)$/i) # rubocop:disable ThreadSafety/RackMiddlewareInstanceVariable
    end

    def call(env)
      return @app.call(env) unless @enabled

      # Wrap all debugging in error handling - never break the request
      begin
        debug_request(env)
      rescue StandardError => ex
        logger.error "SessionDebugger failed",
          error: ex.message,
          error_class: ex.class.name,
          backtrace: ex.backtrace.first(3)
        # If debugging fails, still process the request
        @app.call(env)
      end
    end

    private

    def debug_request(env)
      # Capture request info
      method       = env['REQUEST_METHOD']
      path         = env['PATH_INFO']
      request_time = Time.now

      # Log incoming request
      logger.debug "Session debug start",
        method: method,
        path: path,
        has_cookie: env['HTTP_COOKIE']&.include?('rack.session') || false

      # Get session before processing
      session_before    = env['rack.session']
      session_id_before = extract_session_id(session_before)

      log_session_state(session_before, session_id_before, 'before')
      verify_redis_state(session_id_before, 'before') if session_id_before

      # Process request
      status, headers, body = @app.call(env)

      # Get session after processing
      session_after    = env['rack.session']
      session_id_after = extract_session_id(session_after)

      log_session_state(session_after, session_id_after, 'after')

      # Check for session ID changes
      if session_id_before != session_id_after
        logger.warn "Session ID changed",
          before: session_id_before,
          after: session_id_after
      end

      # Log Set-Cookie header
      log_cookies(headers['Set-Cookie'])

      # Verify what's in Redis after
      verify_redis_state(session_id_after, 'after') if session_id_after

      # Log response info
      duration_ms = ((Time.now - request_time) * 1000).round(2)
      logger.debug "Session debug complete",
        status: status,
        duration_ms: duration_ms

      [status, headers, body]
    end

    def extract_session_id(session)
      return nil unless session

      if session.respond_to?(:id)
        id = session.id
        if id.respond_to?(:public_id)
          id.public_id
        elsif id.is_a?(String)
          id
        else
          id.to_s
        end
      end
    rescue StandardError => ex
      logger.error "Failed to extract session ID", error: ex.message
      nil
    end

    def log_session_state(session, session_id, phase)
      if session.nil?
        logger.warn "Session is nil", phase: phase
        return
      end

      # Extract authentication-related session data
      auth_keys = %w[
        authenticated authenticated_at authenticated_by
        external_id account_external_id advanced_account_id
        email role locale active_session_id
      ]

      auth_data = {}
      auth_keys.each do |key|
        value = session[key]
        auth_data[key] = value if value
      end

      # Log session state
      begin
        logger.debug "Session state",
          phase: phase,
          session_id: session_id || 'NONE',
          session_class: session.class.name,
          auth_data: auth_data,
          total_keys: session.keys.size,
          all_keys: session.keys.join(', ')

        logger.warn "No auth data in session", phase: phase if auth_data.empty?
      rescue StandardError => ex
        logger.error "Could not read session keys",
          phase: phase,
          error: ex.message
      end
    end

    def verify_redis_state(session_id, phase)
      return unless defined?(Familia)

      begin
        dbclient = Familia.dbclient

        # Try common session key patterns
        key_patterns = [
          "session:#{session_id}",
          "rack:session:#{session_id}",
          session_id
        ]

        key_patterns.each do |key|
          next unless dbclient.exists(key) > 0

          ttl  = dbclient.ttl(key)
          data = dbclient.get(key)

          # Try to parse session data
          parsed = begin
            Marshal.load(data)
          rescue StandardError
            begin
              JSON.parse(data)
            rescue StandardError
              data
            end
          end

          logger.debug "Redis session found",
            phase: phase,
            key: key,
            ttl: ttl,
            data_size: data&.bytesize,
            parsed: parsed.is_a?(Hash)

          return
        end

        # Not found in any pattern
        logger.warn "Redis session missing",
          phase: phase,
          session_id: session_id,
          searched_keys: key_patterns

        # List available session keys for debugging
        all_session_keys = dbclient.keys('*session*')
        if all_session_keys.any?
          logger.debug "Available Redis session keys",
            sample: all_session_keys.first(5),
            total: all_session_keys.size
        end
      rescue StandardError => ex
        logger.error "Redis inspection failed",
          phase: phase,
          error: ex.message
      end
    end

    def log_cookies(set_cookie)
      return logger.warn "No Set-Cookie header" unless set_cookie

      cookies = [set_cookie].flatten
      cookies.each do |cookie|
        next unless cookie&.start_with?('rack.session')

        # Parse cookie attributes (skip first part which contains the value)
        parts = cookie.split(';').map(&:strip)
        _cookie_name_value = parts[0] # Intentionally discarded to avoid logging session data
        attributes = {}
        parts[1..].each do |part|
          if part.include?('=')
            key, value = part.split('=', 2)
            attributes[key.downcase] = value
          else
            attributes[part.downcase] = true
          end
        end

        logger.debug "Session cookie set", attributes: attributes

        # Check for common issues
        logger.warn "Cookie missing HttpOnly" unless attributes['httponly']
        logger.warn "Cookie missing SameSite" unless attributes['samesite']
      end
    end
  end
end
