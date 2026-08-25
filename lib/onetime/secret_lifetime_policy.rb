# lib/onetime/secret_lifetime_policy.rb
#
# frozen_string_literal: true

module Onetime
  # Resolves secret-lifetime ceilings that depend on the request boundary.
  #
  # "Unauthenticated" is an authentication fact, not a complete policy scope:
  #
  # - A guest on a canonical host is unaccountable platform traffic. The
  #   operator-configured anonymous ceiling applies (7 days by default).
  # - A guest on a custom host is creating within an accountable tenant
  #   boundary. The custom domain's owning organization supplies the lifetime
  #   policy (normally 14 days for free plans or 30 days for entitled plans).
  #
  # Do not collapse these branches back into a single anonymous ceiling. The
  # distinction is product policy, not an exception to server-side validation.
  # Both branches remain bounded by config_max and MAX_TTL.
  class SecretLifetimePolicy
    Entitlements = Onetime::Models::Features::WithEntitlements

    class << self
      # Resolve the ceiling for an unauthenticated secret-creation request.
      #
      # @param config_max [Numeric] API/configuration upper bound
      # @param domain_strategy [String, Symbol, nil] classified request host
      # @param display_domain [String, nil] normalized request host
      # @return [Integer] effective ceiling in seconds
      def guest_ceiling(config_max:, domain_strategy:, display_domain:)
        config_max = normalize_config_max(config_max)

        if domain_strategy.to_s == 'custom'
          custom_domain_guest_ceiling(config_max, display_domain)
        else
          canonical_guest_ceiling(config_max)
        end
      end

      private

      # A custom-domain guest consumes storage owned by the domain's
      # organization, so use that organization's plan policy rather than the
      # canonical anonymous ceiling. Billing-disabled organizations resolve to
      # an unlimited plan limit and therefore retain config_max.
      def custom_domain_guest_ceiling(config_max, display_domain)
        domain = Onetime::CustomDomain.from_display_domain(display_domain)
        unless domain.respond_to?(:org_id)
          return unresolved_custom_domain_ceiling(config_max, display_domain)
        end

        organization = Onetime::Organization.load(domain.org_id)
        return unresolved_custom_domain_ceiling(config_max, display_domain) unless organization

        plan_limit = organization.limit_for('secret_lifetime')
        return config_max unless finite_positive?(plan_limit)

        plan_limit = plan_limit.to_i
        if billing_enabled? &&
           plan_limit > Entitlements::DEFAULT_FREE_TTL &&
           !organization.can?('extended_default_expiration')
          plan_limit = Entitlements::DEFAULT_FREE_TTL
        end

        [plan_limit, config_max].min
      rescue StandardError => ex
        OT.le '[SecretLifetimePolicy] Custom-domain guest TTL resolution failed; ' \
              'using canonical guest ceiling',
          { display_domain: display_domain, exception: ex }
        canonical_guest_ceiling(config_max)
      end

      # Failure to resolve a host already classified as custom must not widen
      # storage lifetime. Fall back to canonical guest policy until tenant
      # ownership can be established again.
      def unresolved_custom_domain_ceiling(config_max, display_domain)
        OT.le '[SecretLifetimePolicy] Custom-domain owner unavailable; using canonical guest ceiling',
          { display_domain: display_domain }
        canonical_guest_ceiling(config_max)
      end

      def canonical_guest_ceiling(config_max)
        ceilings = [Entitlements.configured_anonymous_max_ttl, config_max]

        if billing_enabled?
          free_tier_max = Onetime::Organization.free_tier_limits['secret_lifetime.max'].to_i
          ceilings << free_tier_max if free_tier_max.positive?
        end

        ceilings.min
      rescue StandardError => ex
        configured = Entitlements.configured_anonymous_max_ttl
        OT.le '[SecretLifetimePolicy] Canonical guest TTL resolution failed; using configured ceiling',
          { exception: ex, ceiling: configured }
        [configured, config_max].min
      end

      def billing_enabled?
        Onetime::BillingConfig.instance.enabled?
      end

      def finite_positive?(value)
        value.respond_to?(:positive?) && value.positive? &&
          (!value.respond_to?(:finite?) || value.finite?)
      end

      def normalize_config_max(value)
        numeric = value.to_i
        numeric = Entitlements::MAX_TTL unless numeric.positive?
        [numeric, Entitlements::MAX_TTL].min
      end
    end
  end
end
