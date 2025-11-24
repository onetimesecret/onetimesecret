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

        allowed = Application.domain_allowed?(domain)
        status  = allowed ? 200 : 403

        OT.info "[Internal::ACME] Domain check: #{domain} -> #{status}"

        res.status          = status
        res['content-type'] = 'text/plain'
        res.body            = [allowed ? 'OK' : 'Forbidden']
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

      warmup do
        # Warmup is for preloading and preparing the router
        # Actual initialization logic is in initializers/
      end

      protected

      def build_router
        routes_path = File.join(__dir__, 'routes.txt')
        Otto.new(routes_path)
      end

      # Build middleware stack
      def build_middleware_stack
        Rack::Builder.new do
          # Security middleware - MUST be first
          # Only allow requests from localhost (Caddy running on same host)
          use LocalhostOnly

          # Simple logging for debugging (development only)
          use Rack::CommonLogger if Onetime.development?
        end
      end

      class << self
        def domain_allowed?(domain)
          # Load and check if this domain exists in our CustomDomain database
          custom_domain = Onetime::CustomDomain.load_by_display_domain(domain)

          return false if custom_domain.nil?

          # IMPORTANT: Only allow domains that have been verified via DNS TXT record.
          # This proves the customer actually owns the domain before Caddy issues a cert.
          # The ACME HTTP challenge (handled by Caddy) is separate from DNS ownership proof.
          custom_domain.ready?
        rescue StandardError => ex
          OT.le "[Internal::ACME] Error checking domain #{domain}: #{ex.message}"
          false
        end
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
            OT.le "[Internal::ACME] Unauthorized access attempt from #{remote_addr}"
            return [401, { 'content-type' => 'text/plain' }, ['Unauthorized - localhost only']]
          end

          @app.call(env)
        end
      end
    end
  end
end

# Load initializers after application class is defined
require_relative 'initializers/preload_models'
