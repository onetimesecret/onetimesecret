# apps/api/domains/logic/sso_config/put_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/sso_config'
require_relative 'base'
require_relative 'serializers'
require_relative 'change_logger'
require_relative 'ssrf_protection'
require_relative 'saml_fields'

module DomainsAPI
  module Logic
    module SsoConfig
      # PUT Domain SSO Configuration (full replacement)
      #
      # @api Creates or replaces the SSO configuration for a custom domain.
      #   Uses PUT semantics: the request body IS the new state.
      #   Empty string or null clears optional fields.
      #   Requires the requesting user to be an organization owner with manage_sso.
      #
      # Request body:
      # - provider_type: Required. One of: oidc, entra_id, saml (issuerless
      #   providers were removed, #3902)
      # - client_id: Required for oidc and entra_id. OAuth client ID. Not
      #   used by saml (no client credential) — any value sent is discarded.
      # - client_secret: Required for entra_id; optional for OIDC
      #   (public-client/PKCE flows may omit it — see
      #   validate_client_credentials); not used by saml. A PUT that omits it
      #   clears any previously stored secret, per full-replacement semantics.
      # - tenant_id: Required for entra_id provider, empty/null for others
      # - issuer: Required for oidc provider, empty/null for others
      # - idp_sso_service_url, idp_entity_id, idp_cert: Required for saml
      #   (#4450; see SamlFields), cleared for others. idp_cert_fingerprint
      #   (and its ruby-saml siblings) is refused for every provider type.
      # - display_name: Optional. Human-readable name (defaults to empty)
      # - allowed_domains: Optional. Array of allowed email domains (defaults to empty)
      # - enabled: Optional. Boolean to enable/disable SSO (default: false)
      #
      # Response includes the updated config with masked client_secret_masked.
      #
      class PutSsoConfig < Base
        include Serializers
        include ChangeLogger
        include SsrfProtection
        include SamlFields

        VALID_PROVIDER_TYPES = Onetime::CustomDomain::SsoConfig::PROVIDER_TYPES.freeze

        attr_reader :sso_config, :existing_config

        def process_params
          @domain_id        = sanitize_identifier(params['extid'])
          @provider_type    = sanitize_plain_text(params['provider_type'])
          @display_name     = sanitize_plain_text(params['display_name'])
          @client_id        = params['client_id'].to_s.strip
          @client_secret    = params['client_secret'].to_s.strip
          @tenant_id        = sanitize_plain_text(params['tenant_id'])
          @issuer           = sanitize_url(params['issuer'])
          process_saml_params
          @allowed_domains  = parse_allowed_domains(params['allowed_domains'])
          @enabled          = parse_boolean(params['enabled'])
          @enforce_sso_only = parse_boolean(params['enforce_sso_only'])
          @grant_org_scope  = parse_boolean(params['grant_org_scope'])

          # oidc only (#4764); '' = gem default. Stored for oidc, cleared otherwise.
          @token_endpoint_auth_method = normalize_token_endpoint_auth_method(params['token_endpoint_auth_method'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_sso!(@domain_id)

          # Check if config already exists
          @existing_config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(@custom_domain.identifier)

          # Validate provider_type
          validate_provider_type

          # A saml replacement needs the install-wide switch on (#4604; see
          # SamlFields). Before the field checks: nothing the caller sends
          # can satisfy it.
          reject_saml_disabled! if @provider_type == 'saml'

          # Never accepted, whatever the provider type (see SamlFields)
          reject_forbidden_saml_params!

          # Validate client credentials (OAuth-family types only: client_id
          # always; client_secret except for OIDC — see header comment)
          validate_client_credentials

          # Validate provider-specific fields
          validate_provider_specific_fields

          # Validate enforce_sso_only requires enabled (using direct values for PUT semantics)
          validate_enforce_sso_requires_enabled(@enabled, @enforce_sso_only)
        end

        def process
          OT.ld "[PutSsoConfig] Replacing SSO config for domain #{@domain_id} by user #{cust.extid}"

          if @existing_config
            # Audit from the state this write replaced, not from the config
            # raise_concerns loaded (see replace_existing_config)
            replaced    = replace_existing_config
            was_enabled = replaced[:was_enabled]
            log_name_id_format_change_if_rekeyed(replaced[:name_id_format], was_enabled)
            log_sso_change_event(
              event: :domain_sso_config_replaced,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider_type: @provider_type,
              changes: replaced[:changes],
            )
          else
            was_enabled = nil
            create_new_config
            log_sso_change_event(
              event: :domain_sso_config_created,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider_type: @provider_type,
            )
          end

          # Log enabled state change if it occurred
          log_enabled_state_change(was_enabled, @enabled)

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_sso_config(@sso_config),
          }
        end

        def form_fields
          {
            domain_id: @domain_id,
            provider_type: @provider_type,
            display_name: @display_name,
            tenant_id: @tenant_id,
            issuer: @issuer,
            token_endpoint_auth_method: @token_endpoint_auth_method,
            idp_sso_service_url: @idp_sso_service_url,
            idp_entity_id: @idp_entity_id,
            allowed_domains: @allowed_domains,
            enabled: @enabled,
            enforce_sso_only: @enforce_sso_only,
            grant_org_scope: @grant_org_scope,
          }
        end

        private

        def validate_provider_type
          raise_form_error('Provider type is required', field: :provider_type, error_type: :missing) if @provider_type.to_s.empty?

          return if VALID_PROVIDER_TYPES.include?(@provider_type)

          raise_form_error(
            "Invalid provider type. Must be one of: #{VALID_PROVIDER_TYPES.join(', ')}",
            field: :provider_type,
            error_type: :invalid,
          )
        end

        def validate_client_credentials
          # SAML has no client credential (#4450).
          return unless Onetime::CustomDomain::SsoConfig.client_credentials?(@provider_type)

          raise_form_error('Client ID is required', field: :client_id, error_type: :missing) if @client_id.to_s.empty?

          # client_secret required for all providers except OIDC (which supports public clients/PKCE)
          if @client_secret.to_s.empty? && @provider_type != 'oidc'
            raise_form_error('Client secret is required', field: :client_secret, error_type: :missing)
          end
        end

        def validate_provider_specific_fields
          case @provider_type
          when 'oidc'
            if @issuer.to_s.empty?
              raise_form_error('Issuer URL is required for OIDC provider', field: :issuer, error_type: :missing)
            end

            # SSRF prevention: validate issuer URL host is not internal/private
            unless valid_issuer_host?(@issuer)
              raise_form_error(
                'Issuer URL must be a valid HTTPS URL pointing to a public host',
                field: :issuer,
                error_type: :invalid,
              )
            end

            validate_token_endpoint_auth_method!(@token_endpoint_auth_method)
          when 'entra_id'
            if @tenant_id.to_s.empty?
              raise_form_error('Tenant ID is required for Entra ID provider', field: :tenant_id, error_type: :missing)
            end
          when 'saml'
            validate_saml_fields!
          end
        end

        # The provider-scoped fields as they will be stored. '' clears.
        #
        # The SAML trio and the client credentials are mutually exclusive by
        # provider type, and the side the type does not use is CLEARED rather
        # than stored as sent: only the used side was validated above, and an
        # unvalidated trust anchor (or credential) must not sit on the record
        # waiting for a later provider_type flip to make it live. A saml
        # record likewise drops issuer / tenant_id. For the OAuth-family types
        # issuer and tenant_id are stored as sent, as before.
        def replacement_attributes
          provider_attributes
        end

        # PUT writes every safe field, including omitted defaults and provider
        # clears. Diff the persisted shape, not the raw request; the model's
        # allowed_domains setter performs additional normalization.
        def replacement_change_params
          values = replacement_attributes.merge(
            provider_type: @provider_type,
            display_name: @display_name,
            allowed_domains: Onetime::CustomDomain::SsoConfig.normalize_allowed_domains(@allowed_domains),
            enabled: @enabled,
            enforce_sso_only: @enforce_sso_only,
            grant_org_scope: @grant_org_scope,
          )
          SAFE_FIELDS.to_h { |field| [field, values.fetch(field.to_sym)] }
        end

        def create_new_config
          @sso_config = Onetime::CustomDomain::SsoConfig.create!(
            domain_id: @custom_domain.identifier,
            provider_type: @provider_type,
            display_name: @display_name,
            **replacement_attributes,
            allowed_domains: @allowed_domains,
            enabled: @enabled,
            enforce_sso_only: @enforce_sso_only,
            grant_org_scope: @grant_org_scope,
          )
        end

        # Replaces existing SSO config with PUT semantics and returns the
        # state it replaced, for the audit events in #process.
        #
        # raise_concerns loaded @existing_config, and a concurrent PUT or
        # PATCH may have committed since. The replaced state is therefore
        # re-read after WATCH on the record's key, and the write commits only
        # if that key is unchanged at EXEC. On a conflict Familia re-runs the
        # read and the write (3 attempts), so each event describes the state
        # its own write replaced. The pin keeps WATCH, the re-read and
        # MULTI/EXEC on one connection (see Onetime.with_pinned_dbclient).
        #
        # @return [Hash] :changes, :was_enabled and :name_id_format of the
        #   replaced record
        def replace_existing_config
          @sso_config = @existing_config
          replaced    = nil

          written = Onetime.with_pinned_dbclient do
            @sso_config.atomic_write(
              watch_keys: [@sso_config.dbkey],
              pre_check: -> { replaced = read_replaced_state },
            ) { assign_replacement_fields }
          end
          raise Onetime::Problem, "SSO config replacement was not written for domain #{@domain_id}" unless written

          replaced
        rescue Familia::KeyNotFoundError, Familia::OptimisticLockError
          # Deleted since raise_concerns, or still changing after 3 attempts
          raise_form_error(
            'The SSO configuration changed while this update was being saved. Reload it and try again.',
            field: :domain_id,
            error_type: :conflict,
          )
        end

        # Runs between WATCH and MULTI, where reads return stored values while
        # the key is guarded.
        def read_replaced_state
          # Checked here because refresh! (Familia 2.12) tests the raw EXISTS
          # reply, and 0 is truthy: a deleted record would refresh to nothing
          # and leave the stale fields in place.
          raise Familia::KeyNotFoundError, @sso_config.dbkey unless @sso_config.exists?

          @sso_config.refresh!
          {
            changes: compute_sso_changes(@sso_config, replacement_change_params),
            was_enabled: @sso_config.enabled?,
            # A PUT that omits name_id_format restores persistent, which
            # re-keys a record that had another.
            name_id_format: stored_name_id_format(@sso_config),
          }
        end

        # Runs inside the MULTI; atomic_write persists the fields after it.
        def assign_replacement_fields
          # PUT semantics: full replacement - set ALL fields from request
          @sso_config.provider_type    = @provider_type
          @sso_config.display_name     = @display_name    # Empty string clears the field
          # Provider-scoped fields: '' clears. client_secret is empty only for
          # OIDC public clients and SAML (validate_client_credentials requires
          # it otherwise).
          replacement_attributes.each { |name, value| @sso_config.public_send(:"#{name}=", value) }
          @sso_config.allowed_domains  = @allowed_domains # Empty array clears the field
          @sso_config.enabled          = @enabled.to_s
          @sso_config.enforce_sso_only = @enforce_sso_only.to_s
          @sso_config.grant_org_scope  = @grant_org_scope.to_s

          # Update timestamp for replacement
          @sso_config.updated = Familia.now.to_i

          # Fail closed if the request validators above missed a field
          # combination: the model owns the invariants (SsoConfig#validation_errors)
          # and nothing invalid may be committed.
          errors = @sso_config.validation_errors
          raise_form_error(errors.join('; '), error_type: :invalid) if errors.any?
        end

        # Log enabled/disabled state change if it occurred.
        #
        # @param was_enabled [Boolean, nil] Previous enabled state (nil if new config)
        # @param is_enabled [Boolean] New enabled state
        def log_enabled_state_change(was_enabled, is_enabled)
          # Skip if no change (both false, or both true)
          return if was_enabled == is_enabled

          # Log when SSO is enabled (new config or was disabled)
          if is_enabled && (was_enabled.nil? || was_enabled == false)
            log_sso_change_event(
              event: :domain_sso_config_enabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider_type: @provider_type,
            )
          elsif was_enabled == true && !is_enabled
            log_sso_change_event(
              event: :domain_sso_config_disabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider_type: @provider_type,
            )
          end
        end
      end
    end
  end
end
