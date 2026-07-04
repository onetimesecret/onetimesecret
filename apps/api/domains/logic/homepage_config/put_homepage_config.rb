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
      # - signup_enabled: Boolean (optional) — toggles Sign Up link on the homepage
      # - signin_enabled: Boolean (optional) — toggles Sign In link on the homepage
      # - disabled_homepage_variant: String (optional) — gated-homepage variant
      #   (closed | minimal | v1). null/omitted leaves it unchanged; "" resets it
      #   to the deployment default; a recognised id sets it.
      # - secrets_mode: String (optional) — which interactive experience the
      #   enabled homepage presents ('create' | 'incoming'). null/omitted
      #   leaves it unchanged. Setting 'incoming' requires the org to have the
      #   incoming_secrets entitlement AND a ready IncomingConfig (enabled
      #   with at least one recipient) — otherwise the homepage would present
      #   a form with nowhere to deliver.
      #
      class PutHomepageConfig < Base
        attr_reader :homepage_config

        def process_params
          @domain_id                 = sanitize_identifier(params['extid'])
          @enabled                   = parse_boolean(params['enabled'])
          @signup_enabled            = parse_boolean(params['signup_enabled']) if params.key?('signup_enabled')
          @signin_enabled            = parse_boolean(params['signin_enabled']) if params.key?('signin_enabled')
          @disabled_homepage_variant = params['disabled_homepage_variant']
          @secrets_mode              = params['secrets_mode']&.to_s&.strip
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_homepage!(@domain_id)

          validate_secrets_mode!
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
            secrets_mode: @secrets_mode,
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
              secrets_mode: @homepage_config.secrets_mode_value,
              # Server-computed effective enablement (the bootstrap
              # serializer's downgrade rule) so the admin frontend can
              # mirror what anonymous visitors actually get without
              # re-deriving readiness from possibly-stale client state.
              effective_enabled: @homepage_config.effectively_enabled?(custom_domain: @custom_domain),
              signup_enabled: @homepage_config.signup_enabled?,
              signin_enabled: @homepage_config.signin_enabled?,
              disabled_homepage_variant: @homepage_config.disabled_homepage_variant_value,
              created_at: @homepage_config.created.to_i,
              updated_at: @homepage_config.updated.to_i,
            },
          }
        end

        private

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
        # removed, incoming disabled) is handled fail-closed at read time by
        # the bootstrap serializer, so unrelated writes (e.g. auth-link
        # toggles) never get stuck behind an unready incoming config.
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

          # Mirror authorize_domain_incoming! (incoming_config/base.rb): the
          # instance-level feature flag gates every incoming write path, so a
          # flag-off instance cannot point homepages at the incoming form.
          unless OT.conf.dig('features', 'incoming', 'enabled')
            raise_form_error(
              'Incoming secrets is not enabled on this instance',
              error_key: 'api.domains.errors.incoming_secrets_disabled',
              field: :secrets_mode,
              error_type: :forbidden,
            )
          end

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
