# lib/onetime/mail/delivery/smtp2go.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative '../smtp2go_client'

module Onetime
  module Mail
    module Delivery
      # SMTP2GO delivery backend using their v3 email API.
      # Supports multipart text/HTML emails via POST /email/send.
      #
      # Configuration options (via config hash or ENV):
      #   api_key:  SMTP2GO API key (ENV: SMTP2GO_API_KEY)
      #   base_url: Custom API base URL (ENV: SMTP2GO_BASE_URL)
      #   timeout:  Read timeout in seconds
      #   fastaccept: Fire-and-forget mode, default false
      #     (ENV: CUSTOM_MAIL_SMTP2GO_FASTACCEPT)
      #
      # Response semantics: SMTP2GO returns 200 with per-recipient
      # accounting ({succeeded:, failed:, failures: [], email_id:}), so a
      # 200 with failed > 0 is still a delivery failure and must raise —
      # see perform_delivery.
      #
      class Smtp2go < Base
        # Standalone twin of the canonical redaction regex,
        # Onetime::Utils::Strings::EMAIL_PATTERN: unicode local part/domain,
        # atomic group to prevent backtracking. #email_pattern prefers the
        # canonical constant whenever the app is loaded (the same conditional
        # Base#obscure_email uses for OT::Utils), so in-app redaction tracks
        # the vetted corpus; this twin only covers standalone mail-lib loads.
        EMAIL_PATTERN = /\b(?>[\p{L}\p{N}._%+'-]+)@[\p{L}\p{N}.\p{Pd}]+\.\p{L}{2,}\b/

        # Recognized truthy tokens for standalone mail-lib loads, where the
        # canonical strict coercion (Onetime::Utils::Strings.strict_bool!) is
        # not on the load path. Same token set, minus the loud rejection of
        # unrecognized input — see #coerce_fastaccept.
        FASTACCEPT_TRUE_TOKENS = %w[1 true yes on y t].freeze

        def initialize(config = {})
          super
          # Default false: synchronous delivery accounting. SMTP2GO's
          # fastaccept=true is fire-and-forget — the API returns 200 with no
          # succeeded/failed/failures keys, so every delivery failure is
          # invisible. Opt into it only when the latency matters more than
          # knowing a message bounced. Read from @config (string-keyed by
          # Base#initialize) so symbol-keyed callers are not silently ignored.
          @fastaccept = coerce_fastaccept(@config['fastaccept'])
        end

        def perform_delivery(email)
          data = client.post('/email/send', build_payload(email))

          # A 200 response can still report per-recipient failures; treat
          # any failed recipient as a delivery failure so Base#deliver
          # wraps it like every other provider error.
          failed = data['failed'].to_i
          if failed.positive?
            # Failure strings embed the raw recipient address; redact it so
            # the obscure_email discipline holds when log_error and Sentry
            # pick up the message and response_body. The failure reason text
            # survives (downstream code matches on it, e.g.
            # domain_not_provisioned_error? in SendTestEmail).
            failures = Array(data['failures']).map { |entry| redact_emails(entry) }.join('; ')
            raise Smtp2goClient::APIError.new(
              "SMTP2GO reported #{failed} failed recipient(s): #{failures}",
              status_code: 200,
              error_code: 'E_DeliveryFailures',
              response_body: redact_emails(data.to_json)[0, 500],
            )
          end

          # Fail-closed: if response has neither 'succeeded' key nor a non-empty
          # 'email_id', treat as unknown response shape rather than silent success.
          # This guards against fastaccept or API changes omitting accounting keys.
          unless data.key?('succeeded') || data['email_id'].to_s.strip.length.positive?
            raise Smtp2goClient::APIError.new(
              'SMTP2GO response missing delivery accounting',
              status_code: 200,
              error_code: 'E_MissingAccounting',
              response_body: redact_emails(data.to_json)[0, 500],
            )
          end

          data
        end

        def log_error(email, error)
          # Always log error details for SMTP2GO API errors
          if error.is_a?(Smtp2goClient::APIError)
            details = {
              error_class: error.class.name,
              status_code: error.status_code,
              error_code: error.error_code,
              response_body: error.response_body,
            }
            msg     = "[mail] SMTP2GO API error details: #{details.inspect}"
            defined?(OT) && OT.respond_to?(:le) ? OT.le(msg) : warn(msg)

            # Report to Sentry with full context
            if defined?(Sentry) && Sentry.initialized?
              Sentry.capture_exception(error) do |scope|
                scope.set_tags(provider: 'smtp2go', status_code: details[:status_code])
                scope.set_context('smtp2go_error', details)
                scope.set_context(
                  'email',
                  {
                    to: obscure_email(email[:to]),
                    from: email[:from],
                    subject: email[:subject],
                  },
                )
              end
            end
          end
          super
        end

        # Classify SMTP2GO API errors by HTTP status code: 429 and 5xx are
        # transient (retryable), other API errors are fatal (bad input,
        # auth, or recipient-level failures). Network-level errors fall
        # through to Base::NETWORK_ERRORS classification.
        def classify_error(error)
          if error.is_a?(Smtp2goClient::APIError)
            status = error.status_code.to_i
            return :transient if status == 429 || status.between?(500, 599)

            return :fatal
          end

          super
        end

        protected

        def validate_config!
          raise ArgumentError, 'SMTP2GO API key must be configured' if api_key.nil? || api_key.empty?
        end

        private

        # Replace each email address embedded in provider text with a
        # domain-preserving mask. Unlike obscure_email (which masks domains
        # for log/Sentry privacy), tenant-facing error messages must show
        # which domain failed verification — the local-part is redacted,
        # but the domain is kept intact.
        #
        # Example: "no-reply@local-secrets.pet" → "***@local-secrets.pet"
        def redact_emails(text)
          text.to_s.gsub(email_pattern) { |address| mask_local_preserve_domain(address) }
        end

        # Mask the local-part of an email address, preserving the domain.
        # @param address [String] Email address to mask
        # @return [String] Masked address with full domain preserved
        def mask_local_preserve_domain(address)
          return address if address.to_s.empty?

          parts = address.split('@', 2)
          return address unless parts.length == 2

          "***@#{parts[1]}"
        end

        # Coerce the configured fastaccept value to a real boolean. SMTP2GO
        # expects a JSON boolean; a string "false" arriving from ENV or a
        # hand-built config hash would be truthy on their side and silently
        # switch off the per-recipient accounting this backend depends on.
        #
        # Prefers the canonical strict coercion, which raises on an
        # unrecognized token instead of quietly resolving to the default. The
        # standalone mail-lib load (no Onetime::Utils) falls back to token
        # matching, mirroring #email_pattern's twin-constant arrangement.
        def coerce_fastaccept(raw)
          return raw if [true, false].include?(raw)

          if defined?(Onetime::Utils::Strings) && Onetime::Utils::Strings.respond_to?(:strict_bool!)
            return Onetime::Utils::Strings.strict_bool!("smtp2go 'fastaccept'", raw, default: false)
          end

          FASTACCEPT_TRUE_TOKENS.include?(raw.to_s.strip.downcase)
        end

        # The canonical, corpus-pinned pattern when the app is loaded; the
        # inline EMAIL_PATTERN twin otherwise (standalone mail-lib loads).
        def email_pattern
          if defined?(Onetime::Utils::Strings::EMAIL_PATTERN)
            Onetime::Utils::Strings::EMAIL_PATTERN
          else
            EMAIL_PATTERN
          end
        end

        # Build the /email/send payload from the normalized email hash.
        #
        # SMTP2GO expects: sender (string), to (array of strings), subject,
        # text_body always, html_body only when present, Reply-To via
        # custom_headers, and fastaccept controlling sync vs async mode.
        #
        # When fastaccept is true, the message is accepted immediately
        # and dispatched in the background — lower latency but no per-recipient
        # failure detection (succeeded/failed keys omitted from response).
        #
        # When fastaccept is false, the response includes full delivery accounting
        # (succeeded, failed, failures, email_id).
        #
        # @param email [Hash] Normalized email parameters
        # @return [Hash] String-keyed request payload
        def build_payload(email)
          payload = {
            'sender' => email[:from],
            'to' => [email[:to]],
            'subject' => email[:subject],
            'text_body' => email[:text_body],
            'fastaccept' => @fastaccept,
          }

          payload['html_body'] = email[:html_body] if html_content?(email)

          if email[:reply_to] && !email[:reply_to].empty?
            payload['custom_headers'] = [
              { 'header' => 'Reply-To', 'value' => email[:reply_to] },
            ]
          end

          payload
        end

        def client
          @client ||= Smtp2goClient.new(
            api_key: api_key,
            base_url: config['base_url'] || ENV.fetch('SMTP2GO_BASE_URL', nil),
            read_timeout: config['timeout'] || 30,
          )
        end

        def api_key
          @api_key ||= config['api_key'] || ENV.fetch('SMTP2GO_API_KEY', nil)
        end
      end
    end
  end
end
