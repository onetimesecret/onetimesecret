# apps/api/domains/logic/api_config/get_api_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/api_config'
require_relative 'base'

module DomainsAPI
  module Logic
    module ApiConfig
      # Get Domain API Configuration
      #
      # @api Retrieves the API access configuration for a custom domain.
      #   Returns the enabled state. Only accessible by organization owners
      #   with api_access entitlement.
      #
      class GetApiConfig < Base
        attr_reader :api_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_api!(@domain_id)

          @api_config = Onetime::CustomDomain::ApiConfig.find_by_domain_id(@custom_domain.identifier)
        end

        def process
          OT.ld "[GetApiConfig] Getting API config for domain #{@domain_id} by user #{cust.extid}"

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: if @api_config
                      {
                        domain_id: @api_config.domain_id,
                        enabled: @api_config.enabled?,
                        created_at: @api_config.created.to_i,
                        updated_at: @api_config.updated.to_i,
                      }
                    end,
          }
        end
      end
    end
  end
end
