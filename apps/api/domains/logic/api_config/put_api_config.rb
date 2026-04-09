# apps/api/domains/logic/api_config/put_api_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/api_config'
require_relative 'base'

module DomainsAPI
  module Logic
    module ApiConfig
      # Create/Update Domain API Configuration
      #
      # @api Creates or updates the API access configuration for a custom
      #   domain. Sets the enabled state. Requires the requesting user to be
      #   an organization owner with api_access entitlement.
      #
      # Request body:
      # - enabled: Boolean (required)
      #
      class PutApiConfig < Base
        attr_reader :api_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
          @enabled   = parse_boolean(params['enabled'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_api!(@domain_id)
        end

        def process
          OT.ld "[PutApiConfig] domain=#{@custom_domain.identifier} extid=#{@domain_id} enabled=#{@enabled} org=#{@organization.identifier} user=#{cust.extid}"

          @api_config = Onetime::CustomDomain::ApiConfig.upsert(
            domain_id: @custom_domain.identifier,
            enabled: @enabled,
          )

          OT.ld "[PutApiConfig] saved domain=#{@custom_domain.identifier} enabled=#{@api_config.enabled?} updated=#{@api_config.updated}"

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: {
              domain_id: @api_config.domain_id,
              enabled: @api_config.enabled?,
              created_at: @api_config.created.to_i,
              updated_at: @api_config.updated.to_i,
            },
          }
        end
      end
    end
  end
end
