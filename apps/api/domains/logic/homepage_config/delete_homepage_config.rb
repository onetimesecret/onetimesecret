# apps/api/domains/logic/homepage_config/delete_homepage_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/homepage_config'
require_relative 'base'

module DomainsAPI
  module Logic
    module HomepageConfig
      # Delete Domain Homepage Configuration
      #
      # @api Deletes the homepage secrets configuration for a custom domain.
      #   Reverts to default (disabled) behavior.
      #   Requires the requesting user to be an organization owner with homepage_secrets.
      #
      class DeleteHomepageConfig < Base
        attr_reader :homepage_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_homepage!(@domain_id)

          @homepage_config = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@custom_domain.identifier)
          raise_not_found("Homepage configuration not found for domain: #{@domain_id}") if @homepage_config.nil?
        end

        def process
          OT.ld "[DeleteHomepageConfig] Deleting homepage config for domain #{@domain_id} by user #{cust.extid}"

          @homepage_config.destroy!

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
