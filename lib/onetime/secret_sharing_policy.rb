# frozen_string_literal: true

require_relative 'domain_validation/ascii_hostname'

module Onetime
  # Combine policies from the workspace and the authorized sharing domains.
  # A selected domain may belong to another workspace the creator can access.
  class SecretSharingPolicy
    MIN_TTL            = 60
    # Characters that make an address more than one bare mailbox.
    ADDRESS_SEPARATORS = /[\s,;:<>"()\[\]\\]/

    def initialize(organizations: [], domains: [])
      @organizations = organizations.compact.uniq(&:objid)
      @domains       = domains.compact.uniq(&:objid)
      @settings      = @organizations.map(&:sharing_policy)
    end

    def passphrase_required?
      OT.conf.get('site.secret_options.passphrase.required', false) ||
        @settings.any? { |policy| policy.fetch('passphrase_required') } ||
        @domains.any? { |domain| domain.brand_settings.passphrase_required? }
    end

    def configured_max_ttl
      @settings.filter_map { |policy| policy.fetch('max_ttl') }.min
    end

    def max_ttl
      plan_limits = @organizations.map { |org| plan_lifetime(org) }.select(&:positive?)
      [Onetime::Models::Features::WithEntitlements::MAX_TTL, configured_max_ttl, *plan_limits].compact.min
    end

    def clamp_ttl(seconds, ceiling:)
      upper = [ceiling, max_ttl].min
      # A positive operator or plan limit below the creation floor cannot
      # satisfy both bounds. Reject creation rather than exceeding the limit.
      raise Onetime::FormError, 'Maximum secret lifetime is below 60 seconds' if upper < MIN_TTL

      seconds.to_i.clamp(MIN_TTL, upper)
    end

    def recipient_email_mode
      modes = @settings.map { |policy| policy.fetch('recipient_email_mode') }
      return 'disabled' if modes.include?('disabled')
      return 'restricted' if modes.include?('restricted')

      'unrestricted'
    end

    def recipient_email_domains
      lists = @settings.filter_map do |policy|
        policy.fetch('recipient_email_domains') if policy.fetch('recipient_email_mode') == 'restricted'
      end
      lists.reduce(:&) || []
    end

    def recipient_allowed?(email)
      case recipient_email_mode
      when 'unrestricted' then true
      when 'restricted'
        domain = single_address_domain(email)
        key    = domain && Onetime::DomainValidation::AsciiHostname.comparison_key(domain)
        !key.nil? && recipient_email_domains.include?(key)
      else false
      end
    end

    private

    # The domain of a single bare address, or nil. Mail delivery can treat a
    # comma or extra "@" as more than one destination, so a restricted policy
    # must not judge such input by its last domain alone.
    def single_address_domain(email)
      return unless email.is_a?(String) && email.count('@') == 1 && !email.match?(ADDRESS_SEPARATORS)

      local, _, domain = email.partition('@')
      domain unless local.empty? || domain.empty?
    end

    # An organization whose plan cannot be resolved (for example a retired
    # plan raising Billing::PlanCacheMissError) takes the canonical guest
    # ceiling. Skipping its limit instead would widen the lifetime.
    def plan_lifetime(organization)
      organization.limit_for('secret_lifetime')
    rescue StandardError => ex
      OT.le '[SecretSharingPolicy] Plan lifetime resolution failed; using canonical guest ceiling',
        { org_id: organization.objid, exception: ex }
      Onetime::SecretLifetimePolicy.canonical_guest_ceiling(Onetime::Models::Features::WithEntitlements::MAX_TTL)
    end
  end
end
