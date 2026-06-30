# apps/web/core/middleware/request_setup.rb
#
# frozen_string_literal: true

require 'onetime/logger_methods'
require 'onetime/security/csp'

# RequestSetup middleware handles request-level initialization for Web Core.
#
# Responsibilities:
# - Generate CSP nonce and make available to views via req.env['onetime.nonce']
# - Set default Content-Type if not already set
# - Initialize locale from request
#
# This middleware should run after session middleware but before authentication
# and error handling middleware.

module Core
  module Middleware
    class RequestSetup
      include Onetime::LoggerMethods

      def initialize(app, default_content_type: 'text/html; charset=utf-8')
        @app                  = app
        @default_content_type = default_content_type
      end

      # Header names for the two CSP rollout phases. We currently emit the
      # REPORT-ONLY header (browsers report violations but do not block), which is
      # the deliberate first step of this rollout. Promotion to the ENFORCING
      # header (CSP_ENFORCING_HEADER) is a planned follow-up once report data
      # confirms no legitimate inline scripts are missing the per-request nonce.
      CSP_REPORT_ONLY_HEADER = 'content-security-policy-report-only'
      CSP_ENFORCING_HEADER   = 'content-security-policy'

      def call(env)
        setup_request(env)
        status, headers, body = @app.call(env)
        finalize_response(status, headers, body, env)
      end

      private

    def setup_request(env)
      # Generate unique nonce for CSP headers (used by views)
      nonce                = SecureRandom.base64(16)
      env['onetime.nonce'] = nonce

      # Locale is handled by Otto::Locale::Middleware
      # Available via env['otto.locale']

      http_logger.debug 'Request setup complete', { nonce: nonce[0, 8] } if OT.debug?
    end

    def finalize_response(status, headers, body, env)
      # Set default Content-Type if not already set
      headers['content-type'] ||= @default_content_type

      apply_csp_report_only(headers, env)

      [status, headers, body]
    end

    # Emit the hardened, nonce-based Content-Security-Policy for HTML responses.
    #
    # IMPORTANT: this is where the Core web app's CSP header actually gets
    # emitted. The router.enable_csp_with_nonce! call in application.rb only sets
    # an Otto flag and emits NO header on its own; without this method the
    # per-request nonce (env['onetime.nonce']) attached to <script> tags by the
    # view layer would be inert, leaving the user-facing HTML pages with no CSP.
    #
    # ROLLOUT: we deliberately use the REPORT-ONLY header as the first step.
    # Browsers report violations but do not block, so we can collect data before
    # promoting to the enforcing 'content-security-policy' header (a planned
    # follow-up). The policy itself is the same hardened, nonce-only policy the
    # V1 API enforces, built from the shared Onetime::Security::Csp builder.
    #
    # Gating (all must hold; same opt-in gate as the V1 API):
    # - OT.conf.dig('site','security','csp','enabled') == true (strict ==)
    # - the response is HTML
    # - a per-request nonce is present in env
    #
    # Defensive: never overwrite a CSP header (enforcing or report-only) that is
    # already present on the response.
    def apply_csp_report_only(headers, env)
      return if OT.conf.dig('site', 'security', 'csp', 'enabled') != true
      return unless headers['content-type'].to_s.include?('text/html')

      nonce = env['onetime.nonce']
      return if nonce.nil? || nonce.to_s.empty?

      # Don't clobber an existing CSP header of either kind.
      return if headers[CSP_REPORT_ONLY_HEADER] || headers[CSP_ENFORCING_HEADER]

      headers[CSP_REPORT_ONLY_HEADER] = Onetime::Security::Csp.policy(
        nonce: nonce,
        development: OT.conf.dig('development', 'enabled'),
      )
    end
    end
  end
end
