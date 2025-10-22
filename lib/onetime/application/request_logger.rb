# lib/onetime/application/request_logger.rb

module Onetime
  module Application
    class RequestLogger
      CAPTURE_MODES = {
        minimal: [:method, :path, :status, :duration],
        standard: [:method, :path, :status, :duration, :request_id, :ip],
        debug: [:method, :path, :status, :duration, :request_id, :ip,
                :params, :headers, :session_id]
      }.freeze

      def initialize(app, config)
        @app = app
        @config = config
        @logger = SemanticLogger['HTTP']
        @capture = CAPTURE_MODES[config['capture']&.to_sym || :standard]
      end

      def call(env)
        return @app.call(env) if ignored?(env['PATH_INFO'])

        request = Rack::Request.new(env)
        start = Onetime.now_in_μs

        status, headers, body = @app.call(env)
        duration = Onetime.now_in_μs - start

        log_request(request, status, duration)

        [status, headers, body]
      end

      private

      def log_request(request, status, duration)
        payload = build_payload(request, status, duration)
        level = determine_level(status, duration)

        @logger.send(level, 'HTTP Request', payload)
      end

      def build_payload(request, status, duration)
        payload = {}

        payload[:method] = request.request_method if capture?(:method)
        payload[:path] = request.path if capture?(:path)
        payload[:status] = status if capture?(:status)
        payload[:duration] = duration if capture?(:duration)
        payload[:request_id] = request.env['HTTP_X_REQUEST_ID'] if capture?(:request_id)
        payload[:ip] = request.ip if capture?(:ip)
        payload[:params] = redact_params(request.params) if capture?(:params)
        payload[:session_id] = request.session.id if capture?(:session_id)

        if capture?(:headers)
          payload[:headers] = request.env.select { |k, _| k.start_with?('HTTP_') }
        end

        payload
      end

      def capture?(field)
        @capture.include?(field)
      end

      def determine_level(status, duration)
        return :error if status >= 500
        # Convert microseconds to milliseconds for comparison with config
        duration_ms = duration / 1000.0
        return :warn if status >= 400 || duration_ms > @config['slow_request_ms']
        @config['level']&.to_sym || :info
      end

      def redact_params(params)
        sensitive = %w[password secret token api_key passphrase access_token refresh_token]
        params.each_with_object({}) do |(k, v), result|
          result[k] = sensitive.include?(k.to_s.downcase) ? '[REDACTED]' : v
        end
      end

      def ignored?(path)
        @config['ignore_paths']&.any? { |pattern| File.fnmatch(pattern, path) }
      end
    end
  end
end
