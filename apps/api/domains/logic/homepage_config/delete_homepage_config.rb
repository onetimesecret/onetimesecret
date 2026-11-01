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
      #   Deleting a config that holds network rules (allowed_cidrs /
      #   denied_cidrs, or an unreadable stored list) also needs what changing
      #   them through PUT needs: the delete drops both lists, and a later PUT
      #   would recreate the homepage without them.
      #
      class DeleteHomepageConfig < Base
        attr_reader :homepage_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_homepage!(@domain_id)

          @homepage_config = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@custom_domain.identifier)
          raise_not_found("Homepage configuration not found for domain: #{@domain_id}") if @homepage_config.nil?

          restricted = restricted_cidr_field
          verify_network_rules_editable!(restricted) if restricted
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

        private

        # The first stored list that holds rules, or that is unreadable
        # (which HomepageConfig#network_allowed? treats as denying everyone).
        #
        # @return [Symbol, nil] :allowed_cidrs | :denied_cidrs
        def restricted_cidr_field
          [:allowed_cidrs, :denied_cidrs].find do |field|
            @homepage_config.public_send(:"#{field}_corrupt?") || !@homepage_config.public_send(field).empty?
          end
        end
      end
    end
  end
end
