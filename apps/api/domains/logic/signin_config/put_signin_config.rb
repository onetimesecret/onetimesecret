# apps/api/domains/logic/signin_config/put_signin_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signin_config'
require_relative 'base'
require_relative 'audit_logger'

module DomainsAPI
  module Logic
    module SigninConfig
      # PUT Domain Signin Configuration (full replacement)
      #
      # @api Creates or replaces the sign-in method configuration for a custom domain.
      #   Uses PUT semantics: the request body IS the new state.
      #   Requires the requesting user to be an organization owner with
      #   custom_signin_config entitlement.
      #
      # Request body:
      # - enabled: Optional boolean (default: false) — master switch
      # - signin_enabled: Optional boolean|null — override AUTH_SIGNIN
      # - restrict_to: Optional string|null — restrict to single auth method
      # - email_auth_enabled: Optional boolean|null — override email auth
      # - sso_enabled: Optional boolean|null — override SSO availability
      #
      class PutSigninConfig < Base
        include AuditLogger

        attr_reader :signin_config, :existing_config

        def process_params
          @domain_id          = sanitize_identifier(params['extid'])
          @enabled            = parse_boolean(params['enabled'])
          @signin_enabled     = parse_nullable_boolean(params['signin_enabled'])
          @restrict_to        = params['restrict_to'].to_s.strip.then { |v| v.empty? ? nil : v }
          @email_auth_enabled = parse_nullable_boolean(params['email_auth_enabled'])
          @sso_enabled        = parse_nullable_boolean(params['sso_enabled'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_signin_config!(@domain_id)

          @existing_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@custom_domain.identifier)

          # Validate restrict_to value
          validate_restrict_to(@restrict_to)
        end

        def process
          OT.ld "[PutSigninConfig] Replacing signin config for domain #{@domain_id} by user #{cust.extid}"

          was_enabled = @existing_config&.enabled?

          if @existing_config
            replace_existing_config
            log_signin_audit_event(
              event: :domain_signin_config_replaced,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          else
            create_new_config
            log_signin_audit_event(
              event: :domain_signin_config_created,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          end

          log_enabled_state_change(was_enabled, @enabled)

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_signin_config(@signin_config),
          }
        end

        def form_fields
          {
            domain_id: @domain_id,
            enabled: @enabled,
            signin_enabled: @signin_enabled,
            restrict_to: @restrict_to,
            email_auth_enabled: @email_auth_enabled,
            sso_enabled: @sso_enabled,
          }
        end

        private

        def create_new_config
          @signin_config = Onetime::CustomDomain::SigninConfig.create!(
            domain_id: @custom_domain.identifier,
            enabled: @enabled,
            signin_enabled: @signin_enabled,
            restrict_to: @restrict_to,
            email_auth_enabled: @email_auth_enabled,
            sso_enabled: @sso_enabled,
          )
        end

        # Replaces existing config with PUT semantics (full replacement).
        def replace_existing_config
          @signin_config = @existing_config

          @signin_config.enabled            = @enabled
          @signin_config.signin_enabled     = @signin_enabled
          @signin_config.restrict_to        = @restrict_to
          @signin_config.email_auth_enabled = @email_auth_enabled
          @signin_config.sso_enabled        = @sso_enabled
          @signin_config.updated            = Familia.now.to_i

          @signin_config.commit_fields
        end

        def serialize_signin_config(config)
          {
            domain_id: @custom_domain.extid,
            enabled: config.enabled?,
            signin_enabled: config.signin_enabled,
            restrict_to: config.restrict_to,
            email_auth_enabled: config.email_auth_enabled,
            sso_enabled: config.sso_enabled,
            created_at: config.created.to_i,
            updated_at: config.updated.to_i,
          }
        end

        # Log enabled/disabled state change if it occurred.
        def log_enabled_state_change(was_enabled, is_enabled)
          return if was_enabled == is_enabled

          if is_enabled && (was_enabled.nil? || was_enabled == false)
            log_signin_audit_event(
              event: :domain_signin_config_enabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          elsif was_enabled == true && !is_enabled
            log_signin_audit_event(
              event: :domain_signin_config_disabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          end
        end
      end
    end
  end
end
