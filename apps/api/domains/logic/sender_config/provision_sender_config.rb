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
        include Onetime::LoggerMethods
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
          provider    = @mailer_config.effective_provider
          from_domain = @mailer_config.from_address&.split('@')&.last

          logger.info 'Starting sender domain provisioning',
            domain_id: @domain_id,
            from_domain: from_domain,
            provider: provider,
            org_id: @organization&.extid,
            user_id: cust.extid

          result = Onetime::Operations::ProvisionSenderDomain.new(
            mailer_config: @mailer_config,
          ).call

          if result.success?
            logger.info 'Sender domain provisioned successfully',
              domain_id: @domain_id,
              from_domain: from_domain,
              provider: provider,
              record_count: result.dns_records.size

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
            logger.error 'Sender domain provisioning failed',
              domain_id: @domain_id,
              from_domain: from_domain,
              provider: provider,
              org_id: @organization&.extid,
              user_id: cust.extid,
              error: result.error

            report_provisioning_failure(result.error, provider, from_domain)

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

        private

        # Report provisioning failures to Sentry for visibility.
        #
        # ProvisionSenderDomain returns Result objects rather than raising,
        # so standard exception capture won't see these. We explicitly report
        # provider failures (HTTP 500, auth errors, rate limits, etc.).
        #
        def report_provisioning_failure(error_message, provider, from_domain)
          return unless defined?(Sentry) && Sentry.initialized?

          Sentry.capture_message("Sender provisioning failed: #{error_message}", level: :error) do |scope|
            scope.set_context(
              'provisioning',
              {
                domain_id: @domain_id,
                from_domain: from_domain,
                provider: provider,
                org_id: @organization&.extid,
                user_id: cust&.extid,
              },
            )
            scope.set_tags(
              operation: 'provision_sender_config',
              provider: provider,
            )
          end
        rescue StandardError => ex
          logger.warn 'Failed to report provisioning failure to Sentry',
            error: ex.message
        end
      end
    end
  end
end
