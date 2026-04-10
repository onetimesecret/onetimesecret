# apps/api/domains/logic/api_config/delete_api_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/api_config'
require_relative 'base'

module DomainsAPI
  module Logic
    module ApiConfig
      # Delete Domain API Configuration
      #
      # @api Deletes the API access configuration for a custom domain.
      #   Reverts to default (disabled) behavior.
      #   Requires the requesting user to be an organization owner with api_access.
      #
      class DeleteApiConfig < Base
        attr_reader :api_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_api!(@domain_id)

          @api_config = Onetime::CustomDomain::ApiConfig.find_by_domain_id(@custom_domain.identifier)
          raise_not_found("API configuration not found for domain: #{@domain_id}") if @api_config.nil?
        end

        def process
          OT.ld "[DeleteApiConfig] Deleting API config for domain #{@domain_id} by user #{cust.extid}"

          @api_config.destroy!

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
