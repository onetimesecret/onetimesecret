# lib/onetime/mail/sender_strategies/base_sender_strategy.rb
#
# frozen_string_literal: true

module Onetime
  module Mail
    module SenderStrategies
      # BaseSenderStrategy - Interface for sender domain provisioning strategies.
      #
      # Sender strategies handle DNS record provisioning for email sender
      # authentication (DKIM, SPF, etc.) through mail provider APIs. This is
      # separate from the Delivery backends which handle actual email sending.
      #
      # Each strategy implements provider-specific logic for:
      #   - Provisioning sender identities and retrieving DNS records
      #   - Checking verification status
      #   - Cleaning up/removing sender identities
      #
      # Strategy Capabilities:
      #
      #   | Strategy   | provision | verify | cleanup |
      #   |------------|-----------|--------|---------|
      #   | SES        | yes       | yes    | yes     |
      #   | SendGrid   | yes       | yes    | yes     |
      #   | Lettermint | yes       | yes    | yes     |
      #   | SMTP       | no-op     | no-op  | no-op   |
      #
      # DNS Record Types by Provider:
      #
      #   SES:       3 CNAME records for DKIM tokens
      #   SendGrid:  Multiple CNAME/TXT records (branded links, DKIM, etc.)
      #   Lettermint: Provider-specific selector records
      #
      class BaseSenderStrategy
        attr_reader :config

        # Initialize with provider configuration.
        #
        # @param config [Hash] Provider-specific configuration (credentials, region, etc.)
        #
        def initialize(config = {})
          @config = config
          validate_config!
        end

        # Provisions sender DNS records through the provider API.
        #
        # This creates or retrieves the sender identity/domain in the provider
        # and returns the DNS records that must be configured for authentication.
        #
        # @param mailer_config [CustomDomain::MailerConfig] The mailer configuration
        # @param credentials [Hash] Provider credentials (api_key, region, etc.)
        # @return [Hash] Provider-specific DNS provisioning data:
        #   - :success [Boolean] Whether provisioning succeeded
        #   - :message [String] Human-readable result
        #   - :dns_records [Array<Hash>] Normalized DNS records, each with:
        #     - :type [String] Record type ('CNAME', 'TXT', etc.)
        #     - :name [String] DNS hostname
        #     - :value [String] DNS record value
        #   - :identity_id [String, nil] Provider's identity identifier
        #   - :error [String, nil] Error message if failed
        #
        def provision_dns_records(mailer_config, credentials:)
          raise NotImplementedError, "#{self.class} must implement #provision_dns_records"
        end

        # Checks the verification status of a sender identity.
        #
        # @param mailer_config [CustomDomain::MailerConfig] The mailer configuration
        # @param credentials [Hash] Provider credentials
        # @return [Hash] Verification status:
        #   - :verified [Boolean] Whether the sender is verified
        #   - :status [String] Provider-specific status code
        #   - :message [String] Human-readable status
        #   - :details [Hash, nil] Additional verification details
        #
        def check_verification_status(mailer_config, credentials:)
          raise NotImplementedError, "#{self.class} must implement #check_verification_status"
        end

        # Removes the sender identity from the provider.
        #
        # @param mailer_config [CustomDomain::MailerConfig] The mailer configuration
        # @param credentials [Hash] Provider credentials
        # @return [Hash] Deletion result:
        #   - :deleted [Boolean] Whether deletion was performed
        #   - :message [String] Human-readable result
        #
        def delete_sender_identity(mailer_config, credentials:)
          raise NotImplementedError, "#{self.class} must implement #delete_sender_identity"
        end

        # Returns the strategy name for logging and debugging.
        #
        # @return [String] Strategy identifier (e.g., 'ses', 'sendgrid')
        #
        def strategy_name
          self.class.name.split('::').last.sub('SenderStrategy', '').downcase
        end

        # Checks if this strategy supports DNS provisioning.
        #
        # SMTP strategy returns false since it doesn't have API-based provisioning.
        #
        # @return [Boolean]
        #
        def supports_provisioning?
          true
        end

        protected

        # Override in subclasses for provider-specific validation.
        #
        def validate_config!
          # Base implementation does nothing
        end

        # Log info message with OT logger fallback.
        #
        # @param message [String] Message to log
        #
        def log_info(message)
          if defined?(OT) && OT.respond_to?(:info)
            OT.info message
          else
            puts message
          end
        end

        # Log error message with OT logger fallback.
        #
        # @param message [String] Message to log
        #
        def log_error(message)
          if defined?(OT) && OT.respond_to?(:le)
            OT.le message
          else
            warn message
          end
        end

        # Extract the domain from an email address.
        #
        # @param email [String] Email address
        # @return [String, nil] Domain portion
        #
        def extract_domain(email)
          return nil if email.to_s.empty?

          parts = email.split('@')
          parts.length == 2 ? parts[1] : nil
        end
      end
    end
  end
end
