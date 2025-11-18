# apps/api/internal/acme/application.rb
#
# frozen_string_literal: true
#
# Internal ACME Application
#
# Provides endpoints for Caddy's on-demand TLS feature to validate
# custom domains before issuing certificates.
#
# Security: This app MUST only respond to requests from localhost/127.0.0.1
# to prevent unauthorized domain validation checks.
#
# Caddy Configuration:
#   on_demand_tls {
#     ask http://127.0.0.1:12020/api/internal/acme/ask
#   }
#
# When Caddy receives a TLS request for a domain, it will call this endpoint
# with ?domain=example.com to check if the domain is allowed.
#
# Response Codes:
#   200 - Domain is allowed (found in CustomDomain database)
#   400 - Bad request (missing domain parameter)
#   401 - Unauthorized (request not from localhost - security violation)
#   403 - Forbidden (domain not found in database)
#   429 - Too Many Requests (rate limit exceeded for domain)
#
# Rate Limiting:
#   - 60 requests per domain per minute
#   - Prevents abuse even from localhost
#   - Uses Redis for distributed rate limiting
#

require 'onetime/application'

module InternalACME
  # Simple Rack application for ACME domain validation
  class Application < Onetime::Application::Base
    @uri_prefix = '/api/internal/acme'

    warmup do
      # Preload CustomDomain model
      require 'onetime/models'
    end

    protected

    def build_router
      router = Otto.new

      # Define the /ask endpoint
      router.add(:GET, '/ask') do |req, res|
        domain = req.params['domain']

        if domain.to_s.empty?
          OT.ld '[InternalACME] Missing domain parameter'
          res.status = 400
          res['content-type'] = 'text/plain'
          res.body = ['Bad Request - domain parameter required']
          next
        end

        allowed = domain_allowed?(domain)
        status = allowed ? 200 : 403

        OT.info "[InternalACME] Domain check: #{domain} -> #{status}"

        res.status = status
        res['content-type'] = 'text/plain'
        res.body = [allowed ? 'OK' : 'Forbidden']
      end

      # Default responses
      router.not_found = [404, { 'content-type' => 'text/plain' }, ['Not Found']]
      router.server_error = [500, { 'content-type' => 'text/plain' }, ['Internal Server Error']]

      router
    end

    # Build middleware stack
    def build_middleware_stack
      Rack::Builder.new do
        # Security middleware - MUST be first
        # Only allow requests from localhost
        use LocalhostOnly

        # Rate limiting to prevent abuse (even from localhost)
        # Limits: 60 requests per domain per minute
        use RateLimiter, limit: 60, window: 60

        # Simple logging for debugging (development only)
        use Rack::CommonLogger if Onetime.development?
      end
    end

    private

    def domain_allowed?(domain)
      # Load and check if this domain exists in our CustomDomain database
      # This uses the class-level display_domains hashkey for O(1) lookup
      custom_domain = Onetime::CustomDomain.load_by_display_domain(domain)

      # Domain is allowed if it exists
      # For Caddy on-demand TLS, we only check if the domain exists
      # in our database. The validation state doesn't matter because
      # Caddy will handle the ACME challenge itself.
      !custom_domain.nil?
    rescue StandardError => e
      OT.le "[InternalACME] Error checking domain #{domain}: #{e.message}"
      false
    end

    # Middleware to restrict access to localhost only
    class LocalhostOnly
      LOCALHOST_IPS = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        remote_addr = env['REMOTE_ADDR']

        unless LOCALHOST_IPS.include?(remote_addr)
          OT.le "[InternalACME] Unauthorized access attempt from #{remote_addr}"
          return [401, { 'content-type' => 'text/plain' }, ['Unauthorized - localhost only']]
        end

        @app.call(env)
      end
    end

    # Middleware to rate limit ACME validation requests
    #
    # Prevents abuse by limiting requests per domain per time window.
    # Uses Redis for distributed rate limiting.
    #
    class RateLimiter
      def initialize(app, limit: 60, window: 60)
        @app = app
        @limit = limit
        @window = window
      end

      def call(env)
        req = Rack::Request.new(env)
        domain = req.params['domain']

        # Skip rate limiting if no domain parameter (will fail with 400 anyway)
        return @app.call(env) if domain.to_s.empty?

        # Check rate limit
        unless check_rate_limit(domain)
          OT.le "[InternalACME] Rate limit exceeded for domain: #{domain}"
          return [429, { 'content-type' => 'text/plain' }, ['Too Many Requests - rate limit exceeded']]
        end

        @app.call(env)
      end

      private

      def check_rate_limit(domain)
        key = "acme:ratelimit:#{domain}"

        # Use Redis to track request counts
        redis = Familia.redis(db: OT.conf.dig('redis', 'databases', 'logs') || 0)

        count = redis.incr(key)
        redis.expire(key, @window) if count == 1

        count <= @limit
      rescue StandardError => ex
        # Log error but allow request to proceed (fail open)
        OT.le "[InternalACME] Rate limit check error: #{ex.message}"
        true
      end
    end
  end
end
