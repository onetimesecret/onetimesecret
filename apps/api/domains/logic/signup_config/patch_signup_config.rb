# apps/api/domains/logic/signup_config/patch_signup_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signup_config'
require_relative 'base'
require_relative 'audit_logger'

module DomainsAPI
  module Logic
    module SignupConfig
      # PATCH Domain Signup Configuration (partial update)
      #
      # @api Partially updates the signup validation configuration for a custom domain.
      #   Uses PATCH semantics: only provided fields are updated; omitted fields
      #   preserve existing data.
      #   Requires the requesting user to be an organization owner with
      #   custom_signup_validation entitlement.
      #
      # Request body:
      # - validation_strategy: Required for create, optional for update (preserves existing if omitted)
      # - allowed_signup_domains: Optional. Array or comma-separated string.
      #   When omitted: preserves existing. When provided as []: clears all.
      # - enabled: Optional. Boolean to enable/disable (preserves existing if omitted)
      #
      class PatchSignupConfig < Base
        include AuditLogger

        VALID_STRATEGY_TYPES = Onetime::CustomDomain::SignupConfig::STRATEGY_TYPES.freeze

        attr_reader :signup_config, :existing_config

        def process_params
          @domain_id                       = sanitize_identifier(params['extid'])
          @validation_strategy             = sanitize_plain_text(params['validation_strategy'])
          # Track whether allowed_signup_domains was explicitly provided (for PATCH semantics)
          @allowed_signup_domains_provided = params.key?('allowed_signup_domains')
          @allowed_signup_domains          = parse_allowed_domains(params['allowed_signup_domains'])
          # Track whether enabled was explicitly provided (for PATCH semantics)
          @enabled_provided                = !params['enabled'].nil?
          @enabled                         = parse_boolean(params['enabled'])
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

          # Resolve effective strategy (PATCH semantics: preserves existing if not provided)
          resolve_strategy

          # Validate domain_allowlist has at least one domain (using effective values)
          effective_domains = @allowed_signup_domains_provided ? @allowed_signup_domains : (@existing_config&.allowed_signup_domains || [])
          validate_allowlist_has_domains(@effective_strategy, effective_domains)

          # Validate domain formats only when explicitly provided
          validate_domain_formats(@allowed_signup_domains) if @allowed_signup_domains_provided
        end

        def process
          OT.ld "[PatchSignupConfig] Patching signup config for domain #{@domain_id} by user #{cust.extid}"

          was_enabled = @existing_config&.enabled?

          if @existing_config
            changes = compute_signup_changes(@existing_config, normalized_change_params)
            update_existing_config
            log_signup_audit_event(
              event: :domain_signup_config_updated,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              validation_strategy: @effective_strategy,
              changes: changes,
            )
          else
            create_new_config
            log_signup_audit_event(
              event: :domain_signup_config_created,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              validation_strategy: @effective_strategy,
            )
          end

          # Use actual state after update (may be unchanged if enabled wasn't provided)
          current_enabled = @signup_config.enabled?
          log_enabled_state_change(was_enabled, current_enabled)

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
            validation_strategy: @effective_strategy,
            allowed_signup_domains: @allowed_signup_domains,
            enabled: @enabled,
          }
        end

        private

        # Build the change-detection payload from parsed/normalized values, not
        # raw params. compute_signup_changes compares against the parsed Array
        # in @existing_config.allowed_signup_domains; if we passed the raw
        # comma-separated string from params, the comparison would mismatch and
        # falsely flag a change in the audit log. We also gate on the same
        # "provided" semantics as the writer (update_existing_config) so a
        # blank validation_strategy that falls back to the existing value is
        # not reported as a change.
        def normalized_change_params
          payload                           = {}
          payload['validation_strategy']    = @effective_strategy unless @validation_strategy.to_s.empty?
          payload['allowed_signup_domains'] = @allowed_signup_domains if @allowed_signup_domains_provided
          payload['enabled']                = @enabled if @enabled_provided
          payload
        end

        # PATCH semantics: strategy preserves existing if not provided.
        # Strategy is still required for new configs.
        def resolve_strategy
          if @validation_strategy.to_s.empty?
            if @existing_config
              @effective_strategy = @existing_config.validation_strategy
            else
              raise_form_error(
                'Validation strategy is required',
                field: :validation_strategy,
                error_type: :missing,
              )
            end
          else
            validate_strategy_type(@validation_strategy)
            @effective_strategy = @validation_strategy
          end
        end

        def create_new_config
          @signup_config = Onetime::CustomDomain::SignupConfig.create!(
            domain_id: @custom_domain.identifier,
            validation_strategy: @effective_strategy,
            allowed_signup_domains: @allowed_signup_domains,
            enabled: @enabled,
          )
        end

        # Updates an existing SignupConfig with PATCH semantics.
        #
        # Only updates fields that were explicitly provided in the request.
        #
        # allowed_signup_domains behavior:
        # - Omitted: preserves existing domains
        # - Provided as []: explicitly clears all existing domains
        # - Provided with values: replaces with new values
        #
        def update_existing_config
          @signup_config                        = @existing_config
          @signup_config.validation_strategy    = @effective_strategy
          @signup_config.allowed_signup_domains = @allowed_signup_domains if @allowed_signup_domains_provided
          @signup_config.enabled                = @enabled.to_s if @enabled_provided
          @signup_config.updated                = Familia.now.to_i

          @signup_config.commit_fields
        end

        def serialize_signup_config(config)
          {
            domain_id: @custom_domain.extid,
            validation_strategy: config.validation_strategy,
            allowed_signup_domains: config.allowed_signup_domains,
            enabled: config.enabled?,
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
              validation_strategy: @effective_strategy,
            )
          elsif was_enabled == true && !is_enabled
            log_signup_audit_event(
              event: :domain_signup_config_disabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              validation_strategy: @effective_strategy,
            )
          end
        end
      end
    end
  end
end
