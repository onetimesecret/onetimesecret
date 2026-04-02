# apps/api/domains/logic/sender_config/provision_sender_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require 'onetime/operations/provision_sender_domain'
require_relative 'base'
require_relative 'serializers'
require_relative 'audit_logger'

module DomainsAPI
  module Logic
    module SenderConfig
      # POST Domain Sender Provisioning
      #
      # @api Provisions sender domain with the configured provider (SES, SendGrid, etc.).
      #   Calls the provider API to register the sender domain and retrieve
      #   DNS records that must be configured for DKIM/SPF verification.
      #   Requires the requesting user to be an organization owner
      #   with custom_mail_sender entitlement.
      #
      # Preconditions:
      # - Sender config must exist for the domain
      # - Provider must be configured (not empty)
      # - Provider must support automated provisioning
      #
      # Response on success:
      # - message: Success message
      # - dns_records: Array of DNS records to configure
      # - sender_config: Updated mailer config with provider_dns_data
      #
      # Response on failure:
      # - error: Error message describing what failed
      #
      class ProvisionSenderConfig < Base
        include Serializers
        include AuditLogger

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

          # Provider is resolved from installation config when not set on mailer_config
          # (see ProvisionSenderDomain#effective_provider)
        end

        def process
          OT.ld "[ProvisionSenderConfig] Provisioning sender domain for #{@domain_id} by user #{cust.extid}"

          result = Onetime::Operations::ProvisionSenderDomain.new(
            mailer_config: @mailer_config,
          ).call

          if result.success?
            log_sender_audit_event(
              event: :domain_sender_provisioned,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider: @mailer_config.provider,
              details: { record_count: result.dns_records.size },
            )

            success_data(result)
          else
            raise_form_error(result.error || 'Provisioning failed', field: :provider, error_type: :operation_failed)
          end
        end

        def success_data(result)
          {
            message: 'Domain provisioned successfully',
            dns_records: result.dns_records,
            record: serialize_sender_config(@mailer_config),
          }
        end
      end
    end
  end
end
