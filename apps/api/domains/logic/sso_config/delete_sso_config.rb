# apps/api/domains/logic/sso_config/delete_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/sso_config'
require_relative 'base'
require_relative 'change_logger'

module DomainsAPI
  module Logic
    module SsoConfig
      # Delete Domain SSO Configuration
      #
      # @api Removes the SSO configuration for a custom domain.
      #   Requires the requesting user to be an organization owner with manage_sso.
      #   Returns 200 with JSON confirmation on success.
      #
      # After deletion, users will no longer be able to authenticate via SSO
      # on this domain. They must use standard email/password authentication
      # or another configured method.
      #
      class DeleteSsoConfig < Base
        include ChangeLogger

        attr_reader :deleted_provider_type

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_sso!(@domain_id)

          # Verify config exists
          return if Onetime::CustomDomain::SsoConfig.exists_for_domain?(@custom_domain.identifier)

          raise_not_found("SSO configuration not found for domain: #{@domain_id}")
        end

        def process
          OT.ld "[DeleteSsoConfig] Deleting SSO config for domain #{@domain_id} by user #{cust.extid}"

          # The audit describes the record as deleted; of concurrent deletes
          # only one gets it (GuardedConfigWrites#remove_for_domain!).
          deleted = guarded_config_write do
            Onetime::CustomDomain::SsoConfig.remove_for_domain!(@custom_domain.identifier)
          end

          if deleted
            @deleted_provider_type = deleted.provider_type

            # Bound to the removed record's generation, so delayed cleanup
            # cannot remove a replacement's outcome; a delete that lost the
            # race leaves cleanup to the one that won. Failed cleanup is
            # harmless to reads: they require a matching config incarnation,
            # and the leftover runtime key has its own TTL.
            begin
              Onetime::CustomDomain::SsoSigninOutcome.delete_for_domain!(@custom_domain.identifier, config: deleted)
            rescue StandardError => ex
              OT.le "[DeleteSsoConfig] sign-in outcome cleanup failed for domain #{@domain_id}: #{ex.class.name}"
            end

            log_sso_change_event(
              event: :domain_sso_config_deleted,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider_type: @deleted_provider_type,
            )
          end

          success_data
        end

        def success_data
          {
            success: true,
            message: "SSO configuration deleted for domain #{@custom_domain.display_domain}",
          }
        end

        def form_fields
          {
            domain_id: @domain_id,
          }
        end
      end
    end
  end
end
