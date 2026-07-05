# apps/api/domains/logic/incoming_config/delete_incoming_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/homepage_config'
require_relative 'base'
require_relative 'serializers'

module DomainsAPI
  module Logic
    module IncomingConfig
      # Delete Domain Incoming Configuration
      #
      # @api Deletes the incoming secrets configuration for a custom domain.
      #   Removes all recipients and disables incoming secrets.
      #   Requires the requesting user to be an organization owner with incoming_secrets.
      #
      # Response includes:
      # - deleted: Boolean indicating success
      # - domain_id: The domain identifier
      #
      class DeleteIncomingConfig < Base
        include Serializers

        attr_reader :incoming_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          # Require authenticated user
          if cust.anonymous?
            raise_form_error(
              'Authentication required',
              error_key: 'api.errors.authentication_required',
              field: :user_id,
              error_type: :authentication_required,
            )
          end

          # Validate domain_id parameter
          if @domain_id.to_s.empty?
            raise_form_error(
              'Domain ID required',
              error_key: 'api.domains.errors.domain_id_required',
              field: :domain_id,
              error_type: :missing,
            )
          end

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_incoming!(@domain_id)

          # Load incoming config
          @incoming_config = Onetime::CustomDomain::IncomingConfig.find_by_domain_id(@custom_domain.identifier)
          return unless @incoming_config.nil?

          raise_not_found(
            "Incoming configuration not found for domain: #{@domain_id}",
            error_key: 'api.domains.errors.incoming_config_not_found',
            args: { extid: @domain_id },
          )
        end

        def process
          OT.ld "[DeleteIncomingConfig] Deleting incoming config for domain #{@domain_id} by user #{cust.extid}"

          @incoming_config.destroy!

          log_homepage_drift

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            deleted: true,
            domain_id: @custom_domain.identifier,
          }
        end

        private

        # Deleting the config un-readies a homepage that points at the
        # incoming form. Deliberately permissive (deleting recipients is a
        # legitimate escape hatch; the bootstrap serializer fails the
        # homepage closed to the trust card) — but leave an audit trail so
        # a silently trust-carded homepage is traceable to this write.
        def log_homepage_drift
          homepage = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@custom_domain.identifier)
          return unless homepage&.enabled? && homepage.incoming_mode?

          OT.li "[DeleteIncomingConfig] domain=#{@custom_domain.identifier} homepage secrets_mode=incoming " \
                "now unready after config delete by user=#{cust.extid}; public homepage degrades to trust card"
        end
      end
    end
  end
end
