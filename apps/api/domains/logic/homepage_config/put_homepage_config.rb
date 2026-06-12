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
      # Request body (optional fields use merge/PATCH-style semantics — an
      # omitted or null value leaves the stored value unchanged):
      # - enabled: Boolean (required)
      # - signup_enabled: Boolean (optional) — toggles Sign Up link on the homepage
      # - signin_enabled: Boolean (optional) — toggles Sign In link on the homepage
      # - disabled_homepage_variant: String (optional) — gated-homepage variant
      #   (closed | minimal | v1). null/omitted leaves it unchanged; "" resets it
      #   to the deployment default; a recognised id sets it.
      #
      class PutHomepageConfig < Base
        attr_reader :homepage_config

        def process_params
          @domain_id                 = sanitize_identifier(params['extid'])
          @enabled                   = parse_boolean(params['enabled'])
          @signup_enabled            = parse_boolean(params['signup_enabled']) if params.key?('signup_enabled')
          @signin_enabled            = parse_boolean(params['signin_enabled']) if params.key?('signin_enabled')
          @disabled_homepage_variant = params['disabled_homepage_variant']
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_homepage!(@domain_id)
        end

        def process
          OT.ld "[PutHomepageConfig] domain=#{@custom_domain.identifier} extid=#{@domain_id} " \
                "enabled=#{@enabled} signup=#{@signup_enabled.inspect} signin=#{@signin_enabled.inspect} " \
                "org=#{@organization.identifier} user=#{cust.extid}"

          @homepage_config = Onetime::CustomDomain::HomepageConfig.upsert(
            domain_id: @custom_domain.identifier,
            enabled: @enabled,
            signup_enabled: @signup_enabled,
            signin_enabled: @signin_enabled,
            disabled_homepage_variant: @disabled_homepage_variant,
          )

          OT.ld "[PutHomepageConfig] saved domain=#{@custom_domain.identifier} " \
                "enabled=#{@homepage_config.enabled?} signup=#{@homepage_config.signup_enabled?} " \
                "signin=#{@homepage_config.signin_enabled?} " \
                "variant=#{@homepage_config.disabled_homepage_variant_value.inspect} " \
                "updated=#{@homepage_config.updated}"

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: {
              domain_id: @homepage_config.domain_id,
              enabled: @homepage_config.enabled?,
              signup_enabled: @homepage_config.signup_enabled?,
              signin_enabled: @homepage_config.signin_enabled?,
              disabled_homepage_variant: @homepage_config.disabled_homepage_variant_value,
              created_at: @homepage_config.created.to_i,
              updated_at: @homepage_config.updated.to_i,
            },
          }
        end
      end
    end
  end
end
