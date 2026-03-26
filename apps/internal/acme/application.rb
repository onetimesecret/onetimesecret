# apps/internal/acme/application.rb
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
#   200 - Domain is allowed (verified in CustomDomain database)
#   400 - Bad request (missing domain parameter)
#   401 - Unauthorized (request not from localhost - security violation)
#   403 - Forbidden (domain not verified or not found)
#

require 'onetime/application'

module Internal
  module ACME
    # Handler for ACME domain validation endpoint
    class AskHandler
      def self.call(req, res)
        domain = req.params['domain']

        if domain.to_s.empty?
          OT.ld '[Internal::ACME] Missing domain parameter'
          res.status          = 400
          res['content-type'] = 'text/plain'
          res.body            = ['Bad Request - domain parameter required']
          return
        end

        # Always verify domain ownership. The check_verification parameter
        # was removed from the HTTP interface to prevent any local process
        # from bypassing DNS verification via query string.
        allowed = Application.domain_allowed?(domain)
        status  = allowed ? 200 : 403

        OT.info "[Internal::ACME] Domain check: #{domain} -> #{status}"

        res.status          = status
        res['content-type'] = 'text/plain'
        res.body            = [allowed ? 'OK' : 'Forbidden']
      end
    end

    # Middleware to restrict access to localhost only.
    #
    # Defined at module level (not inside Application) so it is available
    # for the class-level `use` directive when Application is parsed.
    #
    # Relies on IPPrivacyMiddleware (from the universal MiddlewareStack) running
    # first to resolve the real client IP from forwarded headers into REMOTE_ADDR.
    # If middleware ordering changes, add a Caddy-level block as defense in depth
    # (see README Security section).
    class LocalhostOnly
      def initialize(app)
        @app = app
        # Lazy-load ipaddr as it's part of the standard library but not always needed.
        require 'ipaddr' unless defined?(IPAddr)
      end

      def call(env)
        remote_addr = env['REMOTE_ADDR']
        is_loopback = false

        begin
          # IPAddr.new will raise an error for nil or invalid IP strings.
          is_loopback = remote_addr && IPAddr.new(remote_addr).loopback?
        rescue IPAddr::InvalidAddressError
          # is_loopback remains false, correctly denying the request.
        end

        unless is_loopback
          OT.le "[Internal::ACME] Unauthorized access attempt from #{remote_addr}"
          return [401, { 'content-type' => 'text/plain' }, ['Unauthorized - localhost only']]
        end

        @app.call(env)
      end
    end

    # Simple Rack application for ACME domain validation
    #
    # Design Principles (Microservices Pattern):
    #
    # - No shared configuration: This app intentionally uses Rack::CommonLogger
    #   instead of the main application's RequestLogger. It does not depend on
    #   Onetime.logging_conf to remain self-contained and independent.
    #
    # - Self-contained: All logging decisions are made within this module.
    #   Not coupled to main application's logging infrastructure, allowing
    #   this service to be extracted or deployed independently if needed.
    #
    # - Single responsibility: Validates domains for Caddy's on-demand TLS.
    #   Extremely low traffic (only Caddy calls it), simple logging is sufficient.
    #   Application-level logging happens in the handler for domain validation results.
    #
    class Application < Onetime::Application::Base
      @uri_prefix = '/api/internal/acme'

      # Security: restrict to localhost. Runs after the universal MiddlewareStack
      # (including IPPrivacyMiddleware which resolves the real client IP from
      # forwarded headers), so REMOTE_ADDR reflects the true client even when
      # the main process runs behind a reverse proxy.
      use LocalhostOnly

      # Only load when ACME endpoint is explicitly enabled in config
      def self.should_skip_loading?
        OT.conf&.dig('features', 'domains', 'acme', 'enabled').to_s != 'true'
      end

      warmup do
        # Preload CustomDomain model for ACME validation
        # This prevents lazy loading during Caddy's on-demand TLS requests
        require 'onetime/models'
      end

      protected

      def build_router
        routes_path = File.join(__dir__, 'routes.txt')
        Otto.new(routes_path)
      end

      class << self
        def domain_allowed?(domain, check_verification: true)
          # Load and check if this domain exists in our CustomDomain database
          custom_domain = Onetime::CustomDomain.load_by_display_domain(domain)

          return false if custom_domain.nil?

          return true unless check_verification

          # IMPORTANT: Only allow domains that have been verified via DNS TXT record.
          # This proves the customer actually owns the domain before Caddy issues a cert.
          # The ACME HTTP challenge (handled by Caddy) is separate from DNS ownership proof.
          custom_domain.ready?
        rescue StandardError => ex
          OT.le "[Internal::ACME] Error checking domain #{domain}: #{ex.message}"
          false
        end
      end
    end
  end
end
