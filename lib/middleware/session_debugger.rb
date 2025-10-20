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

module Rack
  class SessionDebugger
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
        puts "\n❌ SessionDebugger Error: #{ex.message}"
        puts "   #{ex.backtrace.first(3).join("\n   ")}"
        puts "   Continuing with request...\n"
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
      log_separator("REQUEST START: #{method} #{path}")

      # Capture incoming cookie
      incoming_cookie = env['HTTP_COOKIE']
      log_info('Incoming Cookie header present', incoming_cookie&.include?('rack.session') || false)

      # Get session before processing
      session_before    = env['rack.session']
      session_id_before = extract_session_id(session_before)

      log_section('SESSION STATE - BEFORE REQUEST')
      log_session_state(session_before, session_id_before, 'before')

      # Verify what's in Redis if we have a session ID
      if session_id_before
        log_redis_state(session_id_before, 'before')
      end

      # Process request
      status, headers, body = @app.call(env)

      # Get session after processing
      session_after    = env['rack.session']
      session_id_after = extract_session_id(session_after)

      log_section('SESSION STATE - AFTER REQUEST')
      log_session_state(session_after, session_id_after, 'after')

      # Check for session ID changes
      if session_id_before != session_id_after
        log_warning("SESSION ID CHANGED: #{session_id_before} -> #{session_id_after}")
      end

      # Log Set-Cookie header
      set_cookie = headers['Set-Cookie']
      log_section('RESPONSE COOKIES')
      if set_cookie
        if set_cookie.is_a?(Array)
          set_cookie.each { |cookie| log_cookie_details(cookie) }
        else
          log_cookie_details(set_cookie)
        end
      else
        log_warning('No Set-Cookie header in response')
      end

      # Verify what's in Redis after
      if session_id_after
        log_redis_state(session_id_after, 'after')
      end

      # Log response info
      duration = ((Time.now - request_time) * 1000).round(2)
      log_separator("REQUEST END: #{status} (#{duration}ms)")
      puts # Blank line for readability

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
      log_error("Failed to extract session ID: #{ex.message}")
      nil
    end

    def log_session_state(session, session_id, _phase)
      if session.nil?
        log_warning('Session is nil')
        return
      end

      log_info('Session ID', session_id || 'NONE')
      log_info('Session class', session.class.name)

      # Log key authentication-related session data
      auth_keys = %w[
        authenticated authenticated_at authenticated_by
        external_id account_external_id advanced_account_id
        email role locale
        active_session_id
      ]

      auth_data = {}
      auth_keys.each do |key|
        value          = session[key]
        auth_data[key] = value if value
      end

      if auth_data.empty?
        log_warning('No authentication data in session')
      else
        log_info('Auth data', Oj.dump(auth_data, indent: 2))
      end

      # Log total number of keys
      begin
        total_keys = session.keys.size
        log_info('Total session keys', total_keys)
        log_info('All keys', session.keys.join(', '))
      rescue StandardError => ex
        log_error("Could not read session keys: #{ex.message}")
      end
    end

    def log_redis_state(session_id, phase)
      return unless defined?(Familia) && Familia.respond_to?(:redis)

      log_section("REDIS STATE - #{phase.upcase}")

      begin
        redis = Familia.dbclient

        # Try common session key patterns
        key_patterns = [
          "session:#{session_id}",
          "rack:session:#{session_id}",
          session_id,
        ]

        found = false
        key_patterns.each do |key|
          next unless redis.exists(key) > 0

          ttl  = redis.ttl(key)
          data = redis.get(key)

          log_info('Redis key', key)
          log_info('TTL', "#{ttl} seconds")

          # Try to parse session data
          begin
            begin
                parsed = begin
                         Marshal.load(data)
                rescue StandardError
                         JSON.parse(data)
                end
            rescue StandardError
                data
            end
            if parsed.is_a?(Hash)
              log_info('Session data', JSON.pretty_generate(parsed))
            else
              log_info('Session data (raw)', data[0..200])
            end
          rescue StandardError
            log_info('Session data (raw)', data[0..200])
          end

          found = true
          break
        end

        unless found
          log_warning("No Redis data found for session ID: #{session_id}")
          log_info('Searched keys', key_patterns.join(', '))

          # List all session keys for debugging
          all_session_keys = redis.keys('*session*')
          if all_session_keys.any?
            log_info('Available session keys in Redis', all_session_keys.first(5).join(', '))
            log_info('Total session keys', all_session_keys.size)
          end
        end
      rescue StandardError => ex
        log_error("Redis inspection failed: #{ex.message}")
      end
    end

    def log_cookie_details(cookie_string)
      return unless cookie_string

      # Parse cookie attributes
      parts             = cookie_string.split(';').map(&:strip)
      cookie_name_value = parts.first

      return unless cookie_name_value&.start_with?('rack.session')

      log_info('Session cookie', 'PRESENT')

      # Log cookie attributes
      attributes = {}
      parts[1..].each do |part|
        if part.include?('=')
          key, value               = part.split('=', 2)
          attributes[key.downcase] = value
        else
          attributes[part.downcase] = true
        end
      end

      log_info('Cookie attributes', attributes.inspect)

      # Check for common issues
      log_warning('Cookie missing HttpOnly flag') unless attributes['httponly']
      log_warning('Cookie missing SameSite attribute') unless attributes['samesite']
      log_warning('Cookie has Secure flag but not in HTTPS') if attributes['secure'] && !https_request?
    end

    def https_request?
      # This would need access to the request env
      # For now, we'll skip this check
      false
    end

    # Logging helpers
    def log_separator(message)
      puts "\n" + ('=' * 80)
      puts "  #{message}"
      puts '=' * 80
    end

    def log_section(message)
      puts "\n" + ('-' * 80)
      puts "  #{message}"
      puts '-' * 80
    end

    def log_info(label, value)
      puts "  #{label.ljust(25)}: #{value}"
    end

    def log_warning(message)
      puts "  ⚠️  WARNING: #{message}"
    end

    def log_error(message)
      puts "  ❌ ERROR: #{message}"
    end
  end
end
