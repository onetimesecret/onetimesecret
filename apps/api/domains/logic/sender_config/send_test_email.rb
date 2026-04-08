# apps/api/domains/logic/sender_config/send_test_email.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require_relative 'base'
require_relative 'audit_logger'

module DomainsAPI
  module Logic
    module SenderConfig
      # Send Test Email for Domain Sender Configuration
      #
      # Sends a test email using the domain's saved email config to verify
      # delivery works before the user enables the feature. The recipient
      # is always the authenticated user's own email address.
      #
      # Key design decisions:
      #   - Does NOT require enabled or verified status on the MailerConfig.
      #     The whole point is testing before committing.
      #   - Does NOT accept a user-supplied recipient. Always sends to the
      #     authenticated user to prevent abuse.
      #   - Bypasses the Mailer's `enabled? && verified?` gate by building
      #     the email hash with from/reply_to pre-populated and calling
      #     deliver_raw without a sender_config. The global backend handles
      #     delivery; we just override the sender identity in the email hash.
      #   - Full authorization (domain ownership + entitlement) is enforced.
      #
      # Response mirrors the SSO TestConnection pattern:
      #   { success: true/false, message: "...", details: { ... } }
      #
      class SendTestEmail < Base
        include AuditLogger

        attr_reader :mailer_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_sender_config!(@domain_id)

          @mailer_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@custom_domain.identifier)
          raise_form_error('No sender configuration found for this domain', field: :domain_id, error_type: :missing) unless @mailer_config

          if @mailer_config.from_address.to_s.empty?
            raise_form_error('Sender configuration must have a from_address before sending a test email', field: :from_address, error_type: :missing)
          end
        end

        def process
          OT.ld "[SendTestEmail] Sending test email for domain #{@domain_id} to #{cust.email}"

          result = send_test_email
          log_test_email_event(result)
          success_data(result)
        end

        def success_data(result = {})
          {
            user_id: cust.extid,
            **result,
          }
        end

        def form_fields
          { domain_id: @domain_id }
        end

        private

        # Build and deliver the test email.
        #
        # Bypasses the Mailer's sender_config gate by constructing the
        # email hash with from/reply_to from the saved config, then
        # calling deliver_raw without a sender_config argument. The
        # backend sends whatever email hash it receives.
        #
        # @return [Hash] Result hash with :success, :message, :details
        def send_test_email
          domain_display = @custom_domain.display_domain
          from_name      = @mailer_config.from_name.to_s.strip
          from_address   = @mailer_config.from_address
          reply_to       = @mailer_config.reply_to
          provider       = @mailer_config.effective_provider || 'default'
          recipient      = cust.email

          # Format the From header with display name if present
          from = if from_name.empty?
                   from_address
                 else
                   "#{from_name} <#{from_address}>"
                 end

          email = {
            to: recipient,
            from: from,
            reply_to: reply_to,
            subject: "Test email from #{domain_display}",
            text_body: build_text_body(domain_display, from_name, from_address, reply_to),
            html_body: build_html_body(domain_display, from_name, from_address, reply_to),
          }

          sent_at = Time.now.utc

          # Use the domain's own API key to build a per-domain backend.
          # The global backend's token is scoped to the platform domain and
          # will be rejected (422) by providers when sending from a custom
          # sender address. Falls back to the global backend if no key stored.
          build_test_backend.deliver(email)

          {
            success: true,
            message: 'Test email sent successfully',
            details: {
              sent_to: recipient,
              from_address: from_address,
              from_name: from_name.empty? ? nil : from_name,
              provider: provider,
              sent_at: sent_at.iso8601,
            },
          }
        rescue Onetime::Mail::DeliveryError => ex
          OT.info "[SendTestEmail] Delivery error for domain #{@domain_id}: #{ex.message}"

          # Check for domain-not-found errors (domain removed from provider)
          if domain_not_provisioned_error?(ex)
            return {
              success: false,
              message: 'Sender domain not found on provider',
              details: {
                error_code: 'domain_not_provisioned',
                description: 'This domain is no longer registered with the email provider. ' \
                             'Please re-provision the sender configuration to restore sending capability.',
              },
            }
          end

          {
            success: false,
            message: 'Failed to send test email',
            details: {
              error_code: ex.transient? ? 'transient_error' : 'delivery_failed',
              description: sanitize_error_message(ex.message),
            },
          }
        rescue StandardError => ex
          OT.le "[SendTestEmail] Unexpected error for domain #{@domain_id}: #{ex.class.name} - #{ex.message}"
          {
            success: false,
            message: 'Failed to send test email',
            details: {
              error_code: 'unexpected_error',
              description: 'An unexpected error occurred while sending the test email. Please try again.',
            },
          }
        end

        # Build a delivery backend using the domain's own API key.
        #
        # Provider tokens are project-scoped — the platform's global token
        # cannot send from a custom sender domain. We decrypt the stored
        # api_key and construct a fresh backend instance for test delivery.
        #
        # Falls back to the global backend if no api_key is stored (e.g.
        # BYOK/SMTP domains where credentials live outside MailerConfig).
        #
        # @return [Onetime::Mail::Delivery::Base]
        def build_test_backend
          provider = @mailer_config.effective_provider
          api_key  = @mailer_config.api_key.to_s.strip

          if api_key.empty?
            OT.info "[SendTestEmail] No domain api_key for #{@domain_id}, using global backend"
            return Onetime::Mail::Mailer.delivery_backend
          end

          case provider
          when 'lettermint'
            Onetime::Mail::Delivery::Lettermint.new(api_token: api_key)
          when 'sendgrid'
            Onetime::Mail::Delivery::SendGrid.new(api_key: api_key)
          else
            # SES requires IAM credentials (key + secret + region) which
            # can't be reconstructed from a single api_key field — fall back
            # to the global backend which has the full SES config.
            OT.info "[SendTestEmail] No per-domain backend for provider=#{provider}, using global"
            Onetime::Mail::Mailer.delivery_backend
          end
        end

        def build_text_body(domain, from_name, from_address, reply_to)
          lines = []
          lines << "Test Email from #{domain}"
          lines << ''
          lines << 'This is a test email sent via Onetime Secret to verify your'
          lines << 'email sender configuration is working correctly.'
          lines << ''
          lines << 'Configuration details:'
          lines << "  Domain:       #{domain}"
          lines << "  From name:    #{from_name.to_s.empty? ? '(not set)' : from_name}"
          lines << "  From address: #{from_address}"
          lines << "  Reply-to:     #{reply_to.to_s.empty? ? '(not set)' : reply_to}"
          lines << ''
          lines << 'If you received this email, your sender configuration is working.'
          lines << 'You can now enable it in your domain settings.'
          lines.join("\n")
        end

        def build_html_body(domain, from_name, from_address, reply_to)
          <<~HTML
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"></head>
            <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; color: #333;">
              <h2 style="color: #1a1a1a; border-bottom: 2px solid #e5e7eb; padding-bottom: 12px;">
                Test Email from #{escape_html(domain)}
              </h2>
              <p>
                This is a test email sent via Onetime Secret to verify your
                email sender configuration is working correctly.
              </p>
              <table style="border-collapse: collapse; margin: 20px 0; width: 100%;">
                <tr>
                  <td style="padding: 8px 12px; font-weight: 600; color: #6b7280; white-space: nowrap;">Domain</td>
                  <td style="padding: 8px 12px;">#{escape_html(domain)}</td>
                </tr>
                <tr style="background: #f9fafb;">
                  <td style="padding: 8px 12px; font-weight: 600; color: #6b7280; white-space: nowrap;">From name</td>
                  <td style="padding: 8px 12px;">#{from_name.to_s.empty? ? '<em style="color:#9ca3af;">(not set)</em>' : escape_html(from_name)}</td>
                </tr>
                <tr>
                  <td style="padding: 8px 12px; font-weight: 600; color: #6b7280; white-space: nowrap;">From address</td>
                  <td style="padding: 8px 12px;">#{escape_html(from_address)}</td>
                </tr>
                <tr style="background: #f9fafb;">
                  <td style="padding: 8px 12px; font-weight: 600; color: #6b7280; white-space: nowrap;">Reply-to</td>
                  <td style="padding: 8px 12px;">#{reply_to.to_s.empty? ? '<em style="color:#9ca3af;">(not set)</em>' : escape_html(reply_to)}</td>
                </tr>
              </table>
              <p style="background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 6px; padding: 12px 16px; color: #166534;">
                If you received this email, your sender configuration is working.
                You can now enable it in your domain settings.
              </p>
            </body>
            </html>
          HTML
        end

        # Minimal HTML escaping for dynamic values in the email body.
        def escape_html(text)
          text.to_s
            .gsub('&', '&amp;')
            .gsub('<', '&lt;')
            .gsub('>', '&gt;')
            .gsub('"', '&quot;')
        end

        # Detect errors indicating the sender domain is not registered with the provider.
        #
        # This happens when a domain was manually removed from the provider dashboard
        # or never provisioned. The provider rejects the send because it doesn't
        # recognize the sender domain.
        #
        # @param ex [Onetime::Mail::DeliveryError] The delivery error
        # @return [Boolean] true if this is a domain-not-provisioned error
        def domain_not_provisioned_error?(ex)
          original = ex.original_error
          return false unless original

          # Lettermint: 422 with "domain" or "sender" in the error message
          if defined?(::Lettermint::HttpRequestError) && original.is_a?(::Lettermint::HttpRequestError)
            return true if original.status_code == 422

            msg = original.message.to_s.downcase
            return true if msg.include?('domain') && (msg.include?('not found') || msg.include?('not registered'))
            return true if msg.include?('sender') && msg.include?('not')
          end

          # SendGrid: 403 with "not verified" in message
          if original.respond_to?(:status_code) && original.status_code == 403
            msg = original.message.to_s.downcase
            return true if msg.include?('not verified') || msg.include?('sender')
          end

          false
        end

        # Remove potentially sensitive information from error messages.
        def sanitize_error_message(message)
          message.to_s
            .gsub(/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, '[IP]')
            .gsub(/:[0-9]+/, ':[PORT]')
            .slice(0, 200)
        end

        def log_test_email_event(result)
          log_sender_audit_event(
            event: :domain_sender_test_email_sent,
            domain: @custom_domain,
            org: @organization,
            actor: cust,
            provider: @mailer_config.effective_provider,
            details: {
              success: result[:success],
              recipient: cust.email,
              from_address: @mailer_config.from_address,
              error_code: result.dig(:details, :error_code),
            }.compact,
          )
        end
      end
    end
  end
end
