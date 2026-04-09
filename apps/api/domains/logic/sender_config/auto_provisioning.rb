# apps/api/domains/logic/sender_config/auto_provisioning.rb
#
# frozen_string_literal: true

require 'onetime/error_handler'

module DomainsAPI
  module Logic
    module SenderConfig
      # Shared auto-provisioning behavior for sender config operations.
      #
      # Includes this module in PatchSenderConfig and PutSenderConfig to
      # DRY up the auto_provision_if_needed method.
      #
      # Requirements for including class:
      # - @mailer_config: MailerConfig instance
      # - @custom_domain: CustomDomain instance
      # - @organization: Organization instance
      # - @domain_id: Domain identifier string
      # - cust: Customer/user performing the action
      # - log_sender_audit_event: Method from AuditLogger module
      #
      module AutoProvisioning
        include Onetime::LoggerMethods

        # Auto-provision DNS records when in platform mode.
        #
        # Platform mode means OTS manages DNS provisioning via the provider API.
        # This is non-blocking: provisioning failures are logged but don't fail
        # the overall save operation.
        #
        # Skips provisioning if:
        # - Already provisioned (dns_records populated)
        # - Sending mode is not 'platform'
        # - Provider doesn't support provisioning
        #
        def auto_provision_if_needed
          return if @mailer_config.provisioned?
          # Platform mode is the only supported mode; treat nil as platform for backwards compat
          return unless @mailer_config.sending_mode.to_s.empty? || @mailer_config.sending_mode == 'platform'

          require 'onetime/operations/provision_sender_domain'

          provider       = @mailer_config.effective_provider
          from_domain    = @mailer_config.from_address&.split('@')&.last
          operation_name = self.class.name.split('::').last

          context = {
            operation: operation_name,
            domain_id: @domain_id,
            from_domain: from_domain,
            provider: provider,
            org_id: @organization&.extid,
            user_id: respond_to?(:cust) ? cust&.extid : nil,
          }

          Onetime::ErrorHandler.safe_execute('auto_provision_sender_domain', **context) do
            result = Onetime::Operations::ProvisionSenderDomain.new(
              mailer_config: @mailer_config,
            ).call

            if result.success?
              logger.info 'Auto-provisioned sender domain',
                domain_id: @domain_id,
                from_domain: from_domain,
                provider: provider,
                record_count: result.dns_records.size

              log_sender_audit_event(
                event: :domain_sender_provisioned,
                domain: @custom_domain,
                org: @organization,
                actor: cust,
                details: { record_count: result.dns_records.size, auto: true },
              )
            else
              # Structured failure (not exception) - log and report to Sentry
              logger.error 'Auto-provisioning failed',
                domain_id: @domain_id,
                from_domain: from_domain,
                provider: provider,
                error: result.error

              report_provisioning_failure(result.error, context)
            end
          end
        end

        private

        # Report non-exception failures to Sentry for visibility.
        #
        # ProvisionSenderDomain returns Result objects rather than raising,
        # so ErrorHandler.safe_execute won't capture these. We explicitly
        # report provider failures (HTTP 500, auth errors, etc.) so they
        # appear in Sentry alongside exception-based errors.
        #
        def report_provisioning_failure(error_message, context)
          return unless defined?(Sentry) && Sentry.initialized?

          Sentry.capture_message("Auto-provisioning failed: #{error_message}", level: :warning) do |scope|
            scope.set_context('provisioning', context)
            scope.set_tags(
              operation: 'auto_provision_sender_domain',
              provider: context[:provider],
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
