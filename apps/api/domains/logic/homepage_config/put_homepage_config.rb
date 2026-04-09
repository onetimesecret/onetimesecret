# apps/api/domains/logic/homepage_config/put_homepage_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/homepage_config'
require_relative 'base'

module DomainsAPI
  module Logic
    module HomepageConfig
      # Create/Update Domain Homepage Configuration
      #
      # @api Creates or updates the homepage secrets configuration for a custom
      #   domain. Sets the enabled state. Requires the requesting user to be an
      #   organization owner with homepage_secrets entitlement.
      #
      # Request body:
      # - enabled: Boolean (required)
      #
      class PutHomepageConfig < Base
        attr_reader :homepage_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
          @enabled   = parse_boolean(params['enabled'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_homepage!(@domain_id)
        end

        def process
          OT.ld "[PutHomepageConfig] Setting homepage config for domain #{@domain_id} enabled=#{@enabled} by user #{cust.extid}"

          @homepage_config = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@custom_domain.identifier)

          if @homepage_config
            @homepage_config.enabled = @enabled.to_s
            @homepage_config.updated = Familia.now.to_i
            @homepage_config.save
          else
            @homepage_config = Onetime::CustomDomain::HomepageConfig.create!(
              domain_id: @custom_domain.identifier,
              enabled: @enabled,
            )
          end

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: {
              domain_id: @homepage_config.domain_id,
              enabled: @homepage_config.enabled?,
              created_at: @homepage_config.created.to_i,
              updated_at: @homepage_config.updated.to_i,
            },
          }
        end
      end
    end
  end
end
