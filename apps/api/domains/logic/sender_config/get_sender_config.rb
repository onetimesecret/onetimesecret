# apps/api/domains/logic/sender_config/get_sender_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require_relative 'base'
require_relative 'serializers'

module DomainsAPI
  module Logic
    module SenderConfig
      # Get Domain Sender Configuration
      #
      # @api Retrieves the mail sender configuration for a custom domain.
      #   Returns the config with masked api_key (only last 4 chars visible).
      #   Requires the requesting user to be an organization owner
      #   with custom_mail_sender entitlement.
      #
      # Response includes:
      # - provider: smtp, ses, sendgrid, lettermint
      # - from_name: Display name for sender
      # - from_address: Sender email address
      # - reply_to: Reply-to address
      # - enabled: Whether sender config is active
      # - verification_status: pending, verified, failed
      # - verified: Boolean shortcut for verification_status == 'verified'
      # - sending_mode: platform or custom
      # - provider_dns_data: Provider-specific DNS records (Hash)
      # - api_key_masked: Masked (e.g., "--------abcd")
      # - created_at: Unix timestamp
      # - updated_at: Unix timestamp
      #
      class GetSenderConfig < Base
        include Serializers

        attr_reader :mailer_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_sender_config!(@domain_id)

          # Load mailer config
          @mailer_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@custom_domain.identifier)
          raise_not_found("Sender configuration not found for domain: #{@domain_id}") if @mailer_config.nil?
        end

        def process
          OT.ld "[GetSenderConfig] Getting sender config for domain #{@domain_id} by user #{cust.extid}"

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_sender_config(@mailer_config),
          }
        end
      end
    end
  end
end
