# apps/api/domains/logic/homepage_config/put_homepage_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/homepage_config'
require 'onetime/models/custom_domain/incoming_config'
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
      # - signup_enabled / signin_enabled: DEPRECATED, ignored (#3672). These
      #   params once toggled the homepage auth links but carry no authority
      #   anymore — per-domain auth links are governed by the SigninConfig /
      #   SignupConfig settings (ADR-030). Submitting them logs a deprecation
      #   warning and leaves the stored fields untouched. The response still
      #   echoes the stored values (all false since the 2026-07-03 migration)
      #   so read-modify-write clients keep round-tripping cleanly until the
      #   fields are removed in a later release.
      # - disabled_homepage_variant: String (optional) — gated-homepage variant
      #   (closed | minimal | v1). null/omitted leaves it unchanged; "" resets it
      #   to the deployment default; a recognised id sets it.
      # - secrets_mode: String (optional) — which interactive experience the
      #   enabled homepage presents ('create' | 'incoming'). null/omitted
      #   leaves it unchanged. Setting 'incoming' requires the org to have the
      #   incoming_secrets entitlement AND a ready IncomingConfig (enabled
      #   with at least one recipient) — otherwise the homepage would present
      #   a form with nowhere to deliver.
      # - allowed_cidrs: Array<String> (optional) — IPv4/IPv6 addresses or
      #   CIDR ranges that may use the interactive homepage. null/omitted
      #   leaves the stored list unchanged; [] clears it (everyone not denied).
      #   Entries are normalized to "address/prefix" and de-duplicated; an
      #   unparseable entry or more than HomepageConfig::MAX_CIDRS entries is
      #   a 422 tagged with the field.
      # - denied_cidrs: Array<String> (optional) — ranges that may never use
      #   it; a deny match wins over the allow list. Same semantics.
      #   Visitors refused by network get the private landing page and a 403
      #   from anonymous secret creation, exactly like a disabled homepage.
      #   Signed-in members and the management pages are never affected, so
      #   an operator cannot lock themselves out of fixing a list.
      #   Sending either list requires the homepage_network_rules entitlement
      #   (Identity Plus) on top of homepage_secrets; see
      #   #verify_network_rules_entitlement!.
      #
      class PutHomepageConfig < Base
        include Onetime::LoggerMethods

        attr_reader :homepage_config

        def process_params
          @domain_id                 = sanitize_identifier(params['extid'])
          @enabled                   = parse_boolean(params['enabled'])
          # Deprecated no-ops (#3672): note their presence for the warning in
          # process, but never parse or persist them — a homepage-form param
          # must not be able to enable an auth surface.
          @deprecated_auth_params    = %w[signup_enabled signin_enabled].select { |key| params.key?(key) }
          @disabled_homepage_variant = params['disabled_homepage_variant']
          @secrets_mode              = params['secrets_mode']&.to_s&.strip
          # Merge semantics: nil (omitted/null) leaves the stored list alone.
          # Shape and entries are validated in raise_concerns, before any write.
          @allowed_cidrs             = params['allowed_cidrs']
          @denied_cidrs              = params['denied_cidrs']
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_homepage!(@domain_id)

          # `enabled` is the master switch and the only always-required field
          # (the others are merge-semantic). Enforce its presence rather than
          # letting a client that omits it silently DISABLE the homepage:
          # parse_boolean(nil) is false, so an omitted field would otherwise
          # read as "turn the homepage off". The request schema already
          # requires it; this makes the server — the authoritative validator —
          # reject the omission instead of trusting the caller.
          raise_form_error('enabled is required', field: :enabled, error_type: :missing) if params['enabled'].nil?

          validate_secrets_mode!
          verify_network_rules_entitlement!
          @allowed_cidrs = validate_cidr_list!(:allowed_cidrs, @allowed_cidrs)
          @denied_cidrs  = validate_cidr_list!(:denied_cidrs, @denied_cidrs)
        end

        def process
          logger.debug "[PutHomepageConfig] domain=#{@custom_domain.identifier} extid=#{@domain_id} " \
                       "enabled=#{@enabled} org=#{@organization.identifier} user=#{cust.extid}"

          if @deprecated_auth_params.any?
            logger.warn "[PutHomepageConfig] deprecated params ignored (#{@deprecated_auth_params.join(', ')}) " \
                        "domain=#{@custom_domain.identifier} user=#{cust.extid} — per-domain homepage auth " \
                        'links are governed by the SigninConfig/SignupConfig settings, not this endpoint (#3672)'
          end

          @homepage_config = Onetime::CustomDomain::HomepageConfig.upsert(
            domain_id: @custom_domain.identifier,
            enabled: @enabled,
            disabled_homepage_variant: @disabled_homepage_variant,
            secrets_mode: @secrets_mode,
            allowed_cidrs: @allowed_cidrs,
            denied_cidrs: @denied_cidrs,
          )

          logger.debug "[PutHomepageConfig] saved domain=#{@custom_domain.identifier} " \
                       "enabled=#{@homepage_config.enabled?} signup=#{@homepage_config.signup_enabled?} " \
                       "signin=#{@homepage_config.signin_enabled?} " \
                       "variant=#{@homepage_config.disabled_homepage_variant_value.inspect} " \
                       "allowed_cidrs=#{@homepage_config.allowed_cidrs.length} " \
                       "denied_cidrs=#{@homepage_config.denied_cidrs.length} " \
                       "updated=#{@homepage_config.updated}"

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: {
              domain_id: @homepage_config.domain_id,
              enabled: @homepage_config.enabled?,
              secrets_mode: @homepage_config.secrets_mode_value,
              # Server-computed effective enablement (the bootstrap
              # serializer's downgrade rule) so the admin frontend can
              # mirror what anonymous visitors actually get without
              # re-deriving readiness from possibly-stale client state.
              effective_enabled: @homepage_config.effectively_enabled?(custom_domain: @custom_domain),
              signup_enabled: @homepage_config.signup_enabled?,
              signin_enabled: @homepage_config.signin_enabled?,
              disabled_homepage_variant: @homepage_config.disabled_homepage_variant_value,
              # Normalized ("address/prefix", de-duplicated) — what the gate
              # actually evaluates, not the entries as typed.
              allowed_cidrs: @homepage_config.allowed_cidrs,
              denied_cidrs: @homepage_config.denied_cidrs,
              created_at: @homepage_config.created.to_i,
              updated_at: @homepage_config.updated.to_i,
            },
          }
        end

        private

        # Require the homepage_network_rules entitlement when a list is sent.
        #
        # Network rules are a paid tier (homepage_network_rules, Identity
        # Plus) layered on homepage_secrets, which the free plan carries. Only
        # a request that sends a list needs it: the experience selector's
        # writes omit both lists and stay available on every plan.
        #
        # Freeze, don't drop, on downgrade: stored rules keep being enforced
        # (no per-request entitlement check on the anonymous paths, and
        # dropping them would widen access), while changing them, clearing
        # included, needs the entitlement back. The draft AccessConfig spec
        # (docs/specs/domain-ip-allowlist) takes the same position for its
        # allowlist.
        def verify_network_rules_entitlement!
          sent = { allowed_cidrs: @allowed_cidrs, denied_cidrs: @denied_cidrs }.compact
          return if sent.empty? || @organization.can?('homepage_network_rules')

          raise_form_error(
            'Homepage network rules require the homepage_network_rules entitlement. Please upgrade your plan.',
            error_key: 'api.entitlements.errors.homepage_network_rules_required',
            field: sent.keys.first,
            error_type: :forbidden,
          )
        end

        # Validate one optional CIDR-list param.
        #
        # nil = merge semantics, leave the stored list unchanged. Anything
        # else must be an Array of strings (rejecting a bare string here
        # rather than letting Array() wrap it keeps the request shape strict),
        # every entry must parse as an IPv4/IPv6 address or range, and the
        # de-duplicated list must fit HomepageConfig::MAX_CIDRS. Returns the
        # normalized list so the write stores exactly what was validated; the
        # model setter re-normalizes (idempotent) as the last line of defence.
        #
        # @param field [Symbol] :allowed_cidrs | :denied_cidrs
        # @param value [Object] raw param value
        # @return [Array<String>, nil]
        def validate_cidr_list!(field, value)
          return nil if value.nil?

          unless value.is_a?(Array) && value.all?(String)
            raise_form_error("#{field} must be an array of strings", field: field, error_type: :invalid)
          end

          Onetime::Utils::CidrList.normalize(value)
        rescue Onetime::Utils::CidrList::InvalidEntry => ex
          raise_form_error(
            "Invalid CIDR: #{ex.entry}",
            error_key: Onetime::CustomDomain::HomepageConfig::InvalidCidr::ERROR_KEY,
            args: { cidr: ex.entry },
            field: field,
            error_type: :invalid,
          )
        rescue Onetime::Utils::CidrList::TooManyEntries => ex
          raise_form_error(
            "#{field} accepts at most #{ex.max} entries",
            error_key: Onetime::CustomDomain::HomepageConfig::TooManyCidrs::ERROR_KEY,
            args: { max: ex.max },
            field: field,
            error_type: :invalid,
          )
        end

        # Validate the optional secrets_mode param.
        #
        # nil = merge semantics, leave stored value unchanged — no checks.
        # Anything else must be a recognised mode (strict rejection rather
        # than the model's silent read-time coercion: silently collapsing a
        # typo'd value to 'create' could switch ON the public create form on
        # a domain that wanted incoming-only).
        #
        # 'incoming' additionally requires the incoming_secrets entitlement
        # and a ready IncomingConfig. Readiness is only enforced when this
        # request explicitly selects incoming mode: later drift (recipients
        # removed, incoming disabled, or the org's incoming_secrets
        # entitlement lapsing) is handled fail-closed at read time by the
        # bootstrap serializer, so unrelated writes (e.g. auth-link toggles,
        # or re-saving `enabled` without `secrets_mode` after a downgrade)
        # never get stuck behind — or accidentally re-validate — a stored
        # 'incoming' selection that's no longer available.
        def validate_secrets_mode!
          return if @secrets_mode.nil?

          unless Onetime::CustomDomain::HomepageConfig::VALID_SECRETS_MODES.include?(@secrets_mode)
            raise_form_error(
              "Invalid secrets_mode: #{@secrets_mode}",
              error_key: 'api.domains.errors.homepage_secrets_mode_invalid',
              args: { secrets_mode: @secrets_mode },
              field: :secrets_mode,
              error_type: :invalid,
            )
          end

          return unless @secrets_mode == 'incoming'

          # Custom-domain incoming is governed by the org's incoming_secrets
          # entitlement, NOT the install-wide features.incoming.enabled flag
          # (which gates the canonical domain only). Mirrors
          # authorize_domain_incoming! (incoming_config/base.rb) and the
          # canonical/custom split in RecipientResolver.
          unless @organization.can?('incoming_secrets')
            raise_form_error(
              'Incoming secrets mode requires the incoming_secrets entitlement. Please upgrade your plan.',
              error_key: 'api.domains.errors.homepage_incoming_entitlement_required',
              field: :secrets_mode,
              error_type: :forbidden,
            )
          end

          incoming = Onetime::CustomDomain::IncomingConfig.find_by_domain_id(@custom_domain.identifier)
          return if incoming&.ready?

          raise_form_error(
            'Incoming secrets must be enabled with at least one recipient before it can be used as the homepage.',
            error_key: 'api.domains.errors.homepage_incoming_not_ready',
            field: :secrets_mode,
            error_type: :invalid,
          )
        end
      end
    end
  end
end
