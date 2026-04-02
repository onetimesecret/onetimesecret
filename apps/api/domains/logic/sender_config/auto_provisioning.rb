# apps/api/domains/logic/sender_config/auto_provisioning.rb
#
# frozen_string_literal: true

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

          result = Onetime::Operations::ProvisionSenderDomain.new(
            mailer_config: @mailer_config,
          ).call

          if result.success?
            OT.ld "[#{self.class.name.split('::').last}] Auto-provisioned DNS records for #{@domain_id}"
            log_sender_audit_event(
              event: :domain_sender_provisioned,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              details: { record_count: result.dns_records.size, auto: true },
            )
          else
            OT.lw "[#{self.class.name.split('::').last}] Auto-provisioning skipped/failed for #{@domain_id}: #{result.error}"
          end
        rescue StandardError => ex
          # Don't fail the save if provisioning fails
          OT.le "[#{self.class.name.split('::').last}] Auto-provisioning error for #{@domain_id}: #{ex.message}"
        end
      end
    end
  end
end
