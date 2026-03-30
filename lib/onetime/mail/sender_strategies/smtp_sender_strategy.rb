# lib/onetime/mail/sender_strategies/smtp_sender_strategy.rb
#
# frozen_string_literal: true

require_relative 'base_sender_strategy'

module Onetime
  module Mail
    module SenderStrategies
      # SMTPSenderStrategy - No-op strategy for SMTP providers.
      #
      # Generic SMTP servers don't have API-based sender authentication
      # provisioning. DNS records (SPF, DKIM) must be configured manually
      # by the domain administrator.
      #
      # All methods return no-op responses indicating that manual
      # configuration is required.
      #
      class SMTPSenderStrategy < BaseSenderStrategy
        # SMTP doesn't support API-based provisioning.
        #
        # @return [Boolean] false
        #
        def supports_provisioning?
          false
        end

        def provision_dns_records(mailer_config, credentials: nil) # rubocop:disable Lint/UnusedMethodArgument
          domain = extract_domain(mailer_config.from_address)

          log_info "[smtp-sender] DNS provisioning not available for SMTP (#{domain})"

          {
            success: false,
            message: 'SMTP providers do not support automated DNS provisioning. ' \
                     'Configure SPF and DKIM records manually with your DNS provider.',
            dns_records: {},
            error: 'provisioning_not_supported',
          }
        end

        def check_verification_status(mailer_config, credentials: nil) # rubocop:disable Lint/UnusedMethodArgument
          domain = extract_domain(mailer_config.from_address)

          log_info "[smtp-sender] Verification check not available for SMTP (#{domain})"

          {
            verified: false,
            status: 'not_supported',
            message: 'SMTP providers do not support verification status checks. ' \
                     'Verify DNS records manually using external tools.',
          }
        end

        def delete_sender_identity(mailer_config, credentials: nil) # rubocop:disable Lint/UnusedMethodArgument
          domain = extract_domain(mailer_config.from_address)

          log_info "[smtp-sender] Identity deletion not applicable for SMTP (#{domain})"

          {
            deleted: false,
            message: 'SMTP providers do not have sender identities to delete.',
          }
        end
      end
    end
  end
end
