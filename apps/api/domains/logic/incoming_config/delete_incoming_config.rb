# apps/api/domains/logic/incoming_config/delete_incoming_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/incoming_config'
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
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_incoming!(@domain_id)

          # Load incoming config
          @incoming_config = Onetime::CustomDomain::IncomingConfig.find_by_domain_id(@custom_domain.identifier)
          raise_not_found("Incoming configuration not found for domain: #{@domain_id}") if @incoming_config.nil?
        end

        def process
          OT.ld "[DeleteIncomingConfig] Deleting incoming config for domain #{@domain_id} by user #{cust.extid}"

          @incoming_config.destroy!

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            deleted: true,
            domain_id: @custom_domain.identifier,
          }
        end
      end
    end
  end
end
