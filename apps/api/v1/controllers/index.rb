# apps/api/v1/controllers/index.rb
#
# frozen_string_literal: true

require 'v1/refinements'

require 'onetime/security/csp_report'

require_relative 'base'
require_relative 'settings'

module V1
  module Controllers
    # V1 Controller Endpoints [#2615]
    #
    # All endpoints that return receipt/secret data use receipt_hsh (via
    # self.class.receipt_hsh) to map internal v0.24 vocabulary back to
    # v0.23.x field names. Each call passes :custid => cust&.email so the
    # response contains the email address, not the internal UUID.
    #
    # The burn response uses :secret_shortkey (v0.23.x name) for the
    # truncated secret identifier, even though the model method is
    # secret_shortid (v0.24 name).
    #
    # GET and POST /private/:key (and aliases /metadata/:key, /receipt/:key)
    # are both routed in v0.24, matching v0.23.x behavior.
    #
    class Index
      include ControllerBase
      include ControllerSettings

      SCHEMAS = {
        status:              { response: 'v1Status' },
        authcheck:           { response: 'v1Status' },
        share:               { response: 'v1Receipt' },
        generate:            { response: 'v1Receipt' },
        create:              { response: 'v1Receipt' },
        show_receipt:        { response: 'v1Receipt' },
        show_receipt_recent: { response: 'v1ReceiptList' },
        show_secret:         { response: 'v1SecretReveal' },
        burn_secret:         { response: 'v1BurnSecret' },
      }.freeze

      @check_utf8 = true
      @check_uri_encoding = true

      # FlexibleHashAccess is a refinement for the Hash class that enables
      # the use of either strings or symbols interchangeably when
      # retrieving values from a hash.
      #
      # @see receipt_hsh method
      #
      using FlexibleHashAccess

      def status
        authorized(true) do
          json :status => :nominal, :locale => locale
        end
      end

      def authcheck
        authorized(false) do
          json :status => :nominal, :locale => locale
        end
      end

      def share
        authorized(true) do
          return if check_rate_limit!(:create_secret, V1_RATE_LIMIT_MAX_CREATES) == :limited

          logic = V1::Logic::Secrets::ConcealSecret.new sess, cust, req.params, locale
          apply_domain_context(logic)
          logic.raise_concerns
          logic.process
          if req.get?
            res.redirect req.app_path(logic.redirect_uri)
          else
            secret = logic.secret
            json self.class.receipt_hsh(logic.receipt,
                                :custid => cust&.email,
                                :secret_ttl => secret.current_expiration,
                                :passphrase_required => secret && secret.has_passphrase?)
          end
        end
      end

      def generate
        authorized(true) do
          return if check_rate_limit!(:create_secret, V1_RATE_LIMIT_MAX_CREATES) == :limited

          logic = V1::Logic::Secrets::GenerateSecret.new sess, cust, req.params, locale
          apply_domain_context(logic)
          logic.raise_concerns
          logic.process
          if req.get?
            res.redirect req.app_path(logic.redirect_uri)
          else
            secret = logic.secret
            json self.class.receipt_hsh(logic.receipt,
                                :custid => cust&.email,
                                :value => logic.secret_value,
                                :secret_ttl => secret.current_expiration,
                                :passphrase_required => secret && secret.has_passphrase?)
            logic.receipt.previewed!
          end
        end
      end

      def show_receipt
        authorized(true) do
          return otto_not_found unless valid_identifier?(req.params['key'])

          logic = V1::Logic::Secrets::ShowReceipt.new sess, cust, req.params, locale
          apply_domain_context(logic)
          logic.raise_concerns
          logic.process
          # Reuse data already loaded/decrypted in logic.process rather than
          # re-loading the secret from Redis and re-decrypting (which can fail).
          if logic.show_secret
            json self.class.receipt_hsh(logic.receipt,
                                :custid => cust&.email,
                                :value => logic.secret_value,
                                :secret_ttl => logic.secret_realttl,
                                :passphrase_required => logic.has_passphrase,
                                :metadata_url => logic.metadata_url)
          else
            json self.class.receipt_hsh(logic.receipt,
                                :custid => cust&.email,
                                :secret_ttl => logic.secret_realttl,
                                :passphrase_required => logic.has_passphrase,
                                :metadata_url => logic.metadata_url)
          end
          logic.receipt.previewed!
        end
      end

      def show_receipt_recent
        authorized(false) do
          logic = V1::Logic::Secrets::ShowReceiptList.new sess, cust, req.params, locale
          apply_domain_context(logic)
          logic.raise_concerns
          logic.process
          recent_receipts = logic.receipts.collect { |md|
            next if md.nil?
            hash = self.class.receipt_hsh(md, :custid => cust&.email)
            hash.delete 'secret_key'  # Don't call md.delete, that will delete from the db
            hash
          }.compact
          json recent_receipts
        end
      end

      def show_secret
        authorized(true) do
          return otto_not_found unless valid_identifier?(req.params['key'])
          return if check_rate_limit!(:show_secret, V1_RATE_LIMIT_MAX_READS) == :limited

          req.params['continue'] = 'true'
          logic = V1::Logic::Secrets::ShowSecret.new sess, cust, req.params, locale
          apply_domain_context(logic)
          logic.raise_concerns
          logic.process
          if logic.show_secret
            json :value => logic.secret_value,
                :secret_key => req.params['key'],
                :share_domain => logic.share_domain
          else
            secret_not_found_response
          end
        end
      end

      # curl -X POST -u 'EMAIL:APITOKEN' http://LOCALHOSTNAME:3000/api/v1/receipt/:key/burn
      def burn_secret
        authorized(true) do
          return otto_not_found unless valid_identifier?(req.params['key'])

          req.params['continue'] = 'true'
          logic = V1::Logic::Secrets::BurnSecret.new sess, cust, req.params, locale
          apply_domain_context(logic)
          logic.raise_concerns
          logic.process
          if logic.greenlighted
            json :state           => self.class.receipt_hsh(logic.receipt, :custid => cust&.email),
                :secret_shortkey => logic.receipt.secret_shortid
          else
            secret_not_found_response
          end
        end
      end

      def create
        authorized(true) do
          return if check_rate_limit!(:create_secret, V1_RATE_LIMIT_MAX_CREATES) == :limited

          logic = V1::Logic::Secrets::ConcealSecret.new sess, cust, req.params, locale
          apply_domain_context(logic)
          logic.raise_concerns
          logic.process
          if req.get?
            res.redirect req.app_path(logic.redirect_uri)
          else
            secret = logic.secret
            json self.class.receipt_hsh(logic.receipt,
                                :custid => cust&.email,
                                :secret_ttl => secret.current_expiration,
                                :passphrase_required => secret && secret.has_passphrase?)
          end
        end
      end

      # Receive browser-posted Content-Security-Policy violation reports.
      #
      # This endpoint is the destination of the report-only CSP emitted by the
      # Core web app (apps/web/core/middleware/request_setup.rb). It is mounted
      # under /api/ so the AuthenticityToken middleware auto-bypasses CSRF
      # (lib/onetime/middleware/security.rb), which is correct: browsers POST CSP
      # reports unauthenticated and without a CSRF token. It is intentionally
      # ANONYMOUS and PUBLIC.
      #
      # Behavior (all mandatory):
      # - STRICT size cap: bodies larger than CspReport::MAX_BODY_BYTES are
      #   skipped without parsing (cheap defense against abuse of a public,
      #   unauthenticated endpoint).
      # - Parses BOTH wire formats: legacy application/csp-report and the
      #   Reporting API application/reports+json. Malformed/empty JSON is
      #   tolerated (logged at debug).
      # - REDACTS every URL-ish field BEFORE logging. This is a secret-sharing
      #   app: document-uri/blocked-uri/referrer/source-file can contain a secret
      #   link (https://host/secret/<KEY>?...). Onetime::Security::CspReport
      #   strips query strings and collapses paths so a secret key can never reach
      #   a log line or Sentry.
      # - NEVER writes to the database and NEVER raises to the client. Always
      #   responds 204 No Content (browsers ignore the response body).
      #
      # Rate limiting: kept deliberately cheap (size cap + no DB + no heavy work)
      # so it is safe to leave unauthenticated. A dedicated per-IP limiter (like
      # check_rate_limit! used elsewhere in this controller) can be layered on as
      # a follow-up if report volume warrants it; infrastructure-layer limiting
      # already fronts the app.
      def csp_report
        body         = read_capped_body
        content_type = req.env['CONTENT_TYPE'] || req.env['HTTP_CONTENT_TYPE']

        summaries = Onetime::Security::CspReport.parse(body, content_type)
        if summaries.empty?
          OT.ld '[csp-report] no parseable violation reports (empty/malformed/oversized)'
        else
          summaries.each { |summary| log_csp_violation(summary) }
        end
      rescue StandardError => ex
        # A violation-report receiver must never surface errors to the browser.
        OT.le "[csp-report] #{ex.class}: #{ex.message}"
      ensure
        res.status = 204
        res.headers.delete('content-type') if res.headers.respond_to?(:delete)
        res.body   = []
      end

      require_relative 'class_methods'
      extend V1::Controllers::ClassMethods

      private

      # Read at most CspReport::MAX_BODY_BYTES + 1 from the request body so an
      # oversized body is detected (and skipped) without ever materializing more
      # than the cap in memory. Returns nil when there is no readable body.
      def read_capped_body
        input = req.env['rack.input'] || req.body
        return nil if input.nil?

        cap   = Onetime::Security::CspReport::MAX_BODY_BYTES
        chunk = input.read(cap + 1)
        input.rewind if input.respond_to?(:rewind)
        chunk
      rescue StandardError => ex
        OT.ld "[csp-report] body read failed: #{ex.class}: #{ex.message}"
        nil
      end

      # Emit ONE redacted, structured log line for a single violation summary.
      # Every value here has already passed through Onetime::Security::CspReport
      # redaction, so no field can carry a secret token. Optionally mirrors the
      # SAME redacted summary to Sentry when available (never raw data).
      def log_csp_violation(summary)
        OT.lw('[csp-report] violation', **csp_log_payload(summary))

        # Optionally mirror the SAME redacted summary to Sentry. Mirrors the
        # sentry_available? guard in lib/onetime/error_handler.rb (that method is
        # private, so we inline the identical check). Never forwards raw data.
        return unless OT.d9s_enabled && defined?(Sentry) && Sentry.initialized?

        Sentry.capture_message('CSP violation report', level: :info) do |scope|
          scope.set_context('csp_report', summary)
        end
      rescue StandardError => ex
        OT.le "[csp-report] logging failed: #{ex.class}: #{ex.message}"
      end

      # Map the redacted summary to a symbol-keyed payload for the structured
      # logger. Only safe fields are included.
      def csp_log_payload(summary)
        {
          violated_directive: summary['violated-directive'],
          effective_directive: summary['effective-directive'],
          disposition: summary['disposition'],
          document_uri: summary['document-uri'],
          blocked_uri: summary['blocked-uri'],
          source_file: summary['source-file'],
          line_number: summary['line-number'],
          column_number: summary['column-number'],
        }.compact
      end
    end
  end
end
