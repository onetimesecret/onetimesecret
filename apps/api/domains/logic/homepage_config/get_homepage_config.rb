# apps/api/domains/logic/homepage_config/get_homepage_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/homepage_config'
require_relative 'base'

module DomainsAPI
  module Logic
    module HomepageConfig
      # Get Domain Homepage Configuration
      #
      # @api Retrieves the homepage secrets configuration for a custom domain.
      #   Returns the enabled state. Only accessible by organization owners
      #   with homepage_secrets entitlement.
      #
      class GetHomepageConfig < Base
        attr_reader :homepage_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_homepage!(@domain_id)

          @homepage_config = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@custom_domain.identifier)
        end

        def process
          OT.ld "[GetHomepageConfig] Getting homepage config for domain #{@domain_id} by user #{cust.extid}"

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: if @homepage_config
                      {
                        domain_id: @homepage_config.domain_id,
                        enabled: @homepage_config.enabled?,
                        created_at: @homepage_config.created.to_i,
                        updated_at: @homepage_config.updated.to_i,
                      }
                    end,
          }
        end
      end
    end
  end
end
