# apps/api/domains/logic/signup_config/put_signup_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signup_config'
require_relative 'base'
require_relative 'audit_logger'

module DomainsAPI
  module Logic
    module SignupConfig
      # PUT Domain Signup Configuration (full replacement)
      #
      # @api Creates or replaces the signup validation configuration for a custom domain.
      #   Uses PUT semantics: the request body IS the new state.
      #   Requires the requesting user to be an organization owner with
      #   custom_signup_validation entitlement.
      #
      # Request body:
      # - validation_strategy: Required. One of: passthrough, domain_allowlist, mx, smtp
      # - allowed_signup_domains: Required for domain_allowlist. Array or comma-separated string
      # - enabled: Optional. Boolean to enable/disable (default: false)
      #
      class PutSignupConfig < Base
        include AuditLogger

        VALID_STRATEGY_TYPES = Onetime::CustomDomain::SignupConfig::STRATEGY_TYPES.freeze

        attr_reader :signup_config, :existing_config

        def process_params
          @domain_id              = sanitize_identifier(params['extid'])
          @validation_strategy    = sanitize_plain_text(params['validation_strategy'])
          @allowed_signup_domains = parse_allowed_domains(params['allowed_signup_domains'])
          @enabled                = parse_boolean(params['enabled'])
          @signup_enabled         = parse_nullable_boolean(params['signup_enabled'])
          @autoverify             = parse_nullable_boolean(params['autoverify'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_signup_config!(@domain_id)

          # Check if config already exists
          @existing_config = Onetime::CustomDomain::SignupConfig.find_by_domain_id(@custom_domain.identifier)

          # Validate strategy type
          if @validation_strategy.to_s.empty?
            raise_form_error(
              'Validation strategy is required',
              field: :validation_strategy,
              error_type: :missing,
            )
          end

          validate_strategy_type(@validation_strategy)

          # Validate domain_allowlist has at least one domain
          validate_allowlist_has_domains(@validation_strategy, @allowed_signup_domains)

          # Validate domain formats before the model setter (which raises Problem -> 500)
          validate_domain_formats(@allowed_signup_domains)
        end

        def process
          OT.ld "[PutSignupConfig] Replacing signup config for domain #{@domain_id} by user #{cust.extid}"

          was_enabled = @existing_config&.enabled?

          if @existing_config
            replace_existing_config
            log_signup_audit_event(
              event: :domain_signup_config_replaced,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              validation_strategy: @validation_strategy,
            )
          else
            create_new_config
            log_signup_audit_event(
              event: :domain_signup_config_created,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              validation_strategy: @validation_strategy,
            )
          end

          log_enabled_state_change(was_enabled, @enabled)

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_signup_config(@signup_config),
          }
        end

        def form_fields
          {
            domain_id: @domain_id,
            validation_strategy: @validation_strategy,
            allowed_signup_domains: @allowed_signup_domains,
            enabled: @enabled,
          }
        end

        private

        def create_new_config
          @signup_config = Onetime::CustomDomain::SignupConfig.create!(
            domain_id: @custom_domain.identifier,
            validation_strategy: @validation_strategy,
            allowed_signup_domains: @allowed_signup_domains,
            enabled: @enabled,
            signup_enabled: @signup_enabled,
            autoverify: @autoverify,
          )
        end

        # Replaces existing config with PUT semantics (full replacement).
        def replace_existing_config
          @signup_config = @existing_config

          @signup_config.validation_strategy    = @validation_strategy
          @signup_config.allowed_signup_domains = @allowed_signup_domains
          @signup_config.enabled                = @enabled.to_s
          @signup_config.signup_enabled         = @signup_enabled
          @signup_config.autoverify             = @autoverify
          @signup_config.updated                = Familia.now.to_i

          @signup_config.commit_fields
        end

        def serialize_signup_config(config)
          {
            domain_id: @custom_domain.extid,
            validation_strategy: config.validation_strategy,
            allowed_signup_domains: config.allowed_signup_domains,
            enabled: config.enabled?,
            signup_enabled: config.signup_enabled,
            autoverify: config.autoverify,
            requires_allowlist: config.requires_allowlist?,
            network_validation: config.network_validation?,
            created_at: config.created.to_i,
            updated_at: config.updated.to_i,
          }
        end

        # Log enabled/disabled state change if it occurred.
        #
        # @param was_enabled [Boolean, nil] Previous enabled state (nil if new config)
        # @param is_enabled [Boolean] New enabled state
        def log_enabled_state_change(was_enabled, is_enabled)
          return if was_enabled == is_enabled

          if is_enabled && (was_enabled.nil? || was_enabled == false)
            log_signup_audit_event(
              event: :domain_signup_config_enabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              validation_strategy: @validation_strategy,
            )
          elsif was_enabled == true && !is_enabled
            log_signup_audit_event(
              event: :domain_signup_config_disabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              validation_strategy: @validation_strategy,
            )
          end
        end
      end
    end
  end
end
