# lib/onetime/application/request_logger.rb
#
# frozen_string_literal: true

module Onetime
  module Application
    class RequestLogger
      CAPTURE_MODES = {
        minimal: [:method, :path, :status, :duration_ms],
        standard: [:method, :path, :status, :duration_ms, :request_id, :ip],
        debug: [:method, :path, :status, :duration_ms, :request_id, :ip,
                :params, :headers, :session_id],
      }.freeze

      def initialize(app, config)
        @app                 = app
        @config              = config
        @logger              = Onetime.get_logger('HTTP')
        @slow_threshold_μs   = (config['slow_request_ms'] || 1000) * 1000

        requested_mode = config['capture']&.to_sym || :standard
        @capture       = CAPTURE_MODES[requested_mode]

        unless @capture
          @capture = CAPTURE_MODES[:standard]
          @logger.warn "Unknown LOG_HTTP_CAPTURE mode '#{requested_mode}', falling back to :standard (valid: #{CAPTURE_MODES.keys.join(', ')})"
        end
      end

      def call(env)
        return @app.call(env) if ignored?(env['PATH_INFO'])

        request = Rack::Request.new(env)
        start   = Onetime.now_in_μs

        status, headers, body = @app.call(env)
        duration_μs           = Onetime.now_in_μs - start  # Duration in microseconds

        log_request(request, status, duration_μs)

        [status, headers, body]
      end

      private

      def log_request(request, status, duration_μs)
        level   = determine_level(status, duration_μs)
        payload = build_payload(request, status, duration_μs)

        @logger.send(level, Familia::JsonSerializer.dump(sanitize_for_json(payload)))
      end

      # Recursively coerce values into JSON-safe primitives so strict
      # serialization never raises on unexpected objects (e.g., uploaded files,
      # tempfiles, IO handles) that may appear under :debug capture mode.
      # Logging must never break request processing.
      def sanitize_for_json(value, depth = 0)
        return '[TOO_DEEP]' if depth > 10

        case value
        when Hash
          value.each_with_object({}) do |(k, v), result|
            result[k.to_s] = sanitize_for_json(v, depth + 1)
          end
        when Array
          value.map { |v| sanitize_for_json(v, depth + 1) }
        when String, Integer, Float, TrueClass, FalseClass, NilClass
          value
        else
          value.to_s
        end
      end

      def build_payload(request, status, duration_μs)
        payload = {}

        payload[:method]     = request.request_method if capture?(:method)
        payload[:path]       = request.path if capture?(:path)
        payload[:status]     = status if capture?(:status)
        payload[:request_id] = request.env['HTTP_X_REQUEST_ID'] if capture?(:request_id)
        payload[:ip]         = request.ip if capture?(:ip)
        payload[:params]     = redact_params(request.params) if capture?(:params)
        # Rack::Session::SessionId is not JSON-serializable under strict mode;
        # prefer public_id (hex digest safe to log) and fall back to to_s.
        if capture?(:session_id) && request.session.respond_to?(:id)
          sid                  = request.session.id
          payload[:session_id] = sid.respond_to?(:public_id) ? sid.public_id : sid.to_s
        end

        if capture?(:headers)
          payload[:headers] = request.env.select { |k, _| k.start_with?('HTTP_') }
        end

        # Add duration_μs last so it appears rightmost in logs
        payload[:duration_ms] = duration_μs / 1000.0 if capture?(:duration_ms)

        payload
      end

      def capture?(field)
        @capture.include?(field)
      end

      # Determine log level based on response status and duration.
      # - 5xx errors → :error
      # - 4xx client errors → :warn
      # - Slow requests (exceeding threshold) → :warn
      # - Normal requests → :info
      def determine_level(status, duration_μs)
        return :error if status >= 500
        return :warn if status >= 400
        return :warn if slow_request?(duration_μs)

        :info
      end

      def slow_request?(duration_μs)
        duration_μs > @slow_threshold_μs
      end

      def redact_params(params)
        sensitive = %w[password secret token api_key passphrase access_token refresh_token]
        params.each_with_object({}) do |(k, v), result|
          result[k] = sensitive.include?(k.to_s.downcase) ? '[REDACTED]' : v
        end
      end

      def ignored?(path)
        return false if path.nil? || @config.nil? || @config['ignore_paths'].nil?

        @config['ignore_paths'].any? { |pattern| File.fnmatch(pattern, path) }
      end
    end
  end
end
