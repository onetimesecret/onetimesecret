# lib/onetime/models/custom_domain/serving_policy.rb
#
# frozen_string_literal: true

module Onetime
  class CustomDomain < Familia::Horreum
    # Whether a registered custom domain is served as a tenant domain.
    #
    # One answer for every consumer that serves, publishes or selects a
    # custom-domain hostname:
    #
    # - Onetime::Middleware::DomainStrategy classifies a registered host
    #   :custom only when #served_as_tenant? is true, and :unverified (answered
    #   with a 404) otherwise.
    # - Secret creation accepts a custom share_domain only on the same answer
    #   (V1/V2 BaseSecretAction#validate_domain_verification).
    # - The domain-context picker lists, and UpdateDomainContext accepts, only
    #   such domains.
    #
    # Auth-link hosts (Auth::PublicHost), tenant SSO, the tenant CSP extras and
    # the ACME ask keep their own, stricter checks on the verified flag (and,
    # for the ask, on resolving). Whether a domain proves an email namespace
    # for tenant SSO is #ownership_proven?, defined here beside the serving
    # answer so the two read together.
    #
    # Every read here uses loaded fields and configuration only: no datastore
    # or DNS I/O.
    module ServingPolicy
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Ownership basis for serving this domain, without the operator's
      # features.domains.serve_unverified setting.
      #
      # - A record with no organization is never served.
      # - Under a validation strategy that does not prove ownership
      #   (passthrough), registration by the owning organization is the basis
      #   (ADR-049), so an owned record is served.
      # - Otherwise ownership must be verified, by the strategy's TXT check or
      #   by a colonel override. Both set ownership_verified.
      #
      # @return [Boolean]
      def serving_authorized?
        return false if org_id.to_s.empty?
        return true unless self.class.ownership_proof_required?

        ownership_verified == true
      end

      # Whether this domain's accepted ownership rests on evidence that its
      # organization owns the name, so tenant SSO may treat the name and the
      # names below it as the organization's email namespace (#4734,
      # RISK-2026-10-10-01). Organization#verified_domains and every tenant
      # SSO email domain check read it.
      #
      # - A Colonel override (verified_by_override) counts under any
      #   strategy: an operator asserted ownership for this one name.
      # - Otherwise two things must both be true: the install's validation
      #   strategy checks the TXT record (ownership_proof_checked?), and a
      #   passing check is on record for this domain (#txt_pass_recorded?,
      #   from verified_confirmed_at). VerifyDomain writes that epoch only
      #   for a pass from a strategy that proves ownership
      #   (Operations::VerifyDomain::ConfirmationWindow#record_settled).
      #
      # ownership_verified alone is not evidence, even under a TXT strategy.
      # A passthrough pass sets it for any name the organization registers,
      # without a DNS lookup, and records no confirmation
      # (ConfirmationWindow#record_skipped); ADR-049 calls that operator
      # policy "an authorization basis, not evidence that the customer owns
      # the hostname". A domain verified before v0.26.14, when the
      # confirmation field did not exist, and not checked since has the flag
      # and no record either. ADR-016 treats such a domain as never confirmed
      # once the install moves to caddy_on_demand, and ADR-049 says a switch
      # to either TXT strategy stops operator-policy authorization from
      # qualifying at once, before any refresh, and that a persisted verified
      # flag may not satisfy the check by itself. So the switch must not
      # promote a flag no check ever backed: the domain counts once bin/ots
      # domains verify or the scheduled refresh records a pass. A later
      # failing check withdraws ownership_verified, which is read first, so a
      # stale record of an earlier pass never counts on its own.
      #
      # Stricter than #serving_authorized?, which accepts registration alone
      # under passthrough. Serving a name is not the same as owning the
      # mailboxes under it. The two also fail in opposite directions when the
      # strategy cannot be built: serving then requires ownership_verified,
      # and proof then requires an override.
      #
      # Reads loaded fields and configuration only: no datastore or DNS I/O.
      #
      # @return [Boolean]
      def ownership_proven?
        return false unless ownership_verified == true
        return true if verified_by_override == true

        self.class.ownership_proof_checked? && txt_pass_recorded?
      end

      # Whether a passing TXT check is on record for this domain:
      # verified_confirmed_at (an integer_field, read back as Integer or
      # nil) is an epoch after zero. nil, an empty string and 0 all mean no
      # pass. Says nothing about which strategy is configured now; that is
      # #ownership_proven?.
      #
      # @return [Boolean]
      def txt_pass_recorded?
        verified_confirmed_at.to_i.positive?
      end

      # #serving_authorized?, or any record with an organization while the
      # operator has set features.domains.serve_unverified to true. A record
      # with no organization is never served, whatever the setting.
      #
      # @return [Boolean]
      def served_as_tenant?
        return false if org_id.to_s.empty?

        serving_authorized? || self.class.serve_unverified?
      end

      # Why this record is not served, for logs: :orphan (no organization),
      # :unverified (ownership not verified), or nil when it is served.
      #
      # @return [Symbol, nil]
      def unserved_reason
        return nil if served_as_tenant?

        org_id.to_s.empty? ? :orphan : :unverified
      end

      module ClassMethods
        SERVE_UNVERIFIED_WARNING = Mutex.new
        private_constant :SERVE_UNVERIFIED_WARNING

        # Whether serving requires ownership_verified, that is, whether the
        # install's validation strategy proves ownership
        # (Onetime::DomainValidation::BaseStrategy#proves_ownership?):
        # true for approximated and caddy_on_demand, false for passthrough.
        #
        # A strategy that cannot be built (an unknown name under
        # strict_strategy) answers true, so serving fails closed.
        #
        # @return [Boolean]
        def ownership_proof_required?
          validation_strategy_state != :no_proof
        end

        # Whether the install's strategy is known to check the TXT record
        # (approximated, caddy_on_demand), so that a recorded pass counts as
        # evidence of ownership for #ownership_proven?.
        #
        # A strategy that cannot be built answers false, so proof fails
        # closed and only a Colonel override counts.
        #
        # @return [Boolean]
        def ownership_proof_checked?
          validation_strategy_state == :proves
        end

        # What the configured validation strategy does about ownership:
        # :proves (it checks the TXT record), :no_proof (passthrough), or
        # :unbuildable (Strategy.for_config raised, for example an unknown
        # name under strict_strategy).
        #
        # Decided from the same configuration Strategy.for_config reads, and
        # kept for as long as that configuration is unchanged. A different
        # validation_strategy or strict_strategy value (a spec that swaps
        # OT.conf) is decided again on the next call; nothing has to be reset.
        #
        # @return [Symbol]
        def validation_strategy_state
          domains = configured_domains_section
          key     = [domains['validation_strategy'], domains['strict_strategy'] == true]
          decided = @validation_strategy_state
          return decided.last if decided && decided.first == key

          state                      = decide_validation_strategy_state(domains)
          @validation_strategy_state = [key, state].freeze
          state
        end

        # features.domains.serve_unverified, read as a strict boolean. When
        # true, a record with an organization is served whatever its
        # ownership state (#served_as_tenant?).
        #
        # @return [Boolean]
        def serve_unverified?
          configured_domains_section['serve_unverified'] == true
        end

        # Logs one warning per process while features.domains.serve_unverified
        # is true. Called at boot by Onetime::Initializers::ConfigureDomains;
        # serving a request logs nothing.
        #
        # @return [Boolean] whether this call logged the warning
        def warn_if_serve_unverified
          return false unless serve_unverified?

          SERVE_UNVERIFIED_WARNING.synchronize do
            return false if @serve_unverified_warned

            @serve_unverified_warned = true
          end

          Onetime.get_logger('App').warn 'custom_domain.serve_unverified_enabled',
            {
              setting: 'features.domains.serve_unverified',
              effect: 'custom domains that have an organization are served whatever their ownership state',
            }
          true
        end

        # Clears the decided strategy and the warning latch. For specs.
        #
        # @return [void]
        def reset_serving_policy!
          SERVE_UNVERIFIED_WARNING.synchronize do
            @validation_strategy_state = nil
            @serve_unverified_warned   = false
          end
        end

        private

        def configured_domains_section
          domains = OT.conf&.get('features.domains', {})
          domains.is_a?(Hash) ? domains : {}
        end

        def decide_validation_strategy_state(domains)
          require_relative '../../domain_validation/strategy'

          config = { 'features' => { 'domains' => domains } }
          Onetime::DomainValidation::Strategy.for_config(config).proves_ownership? == true ? :proves : :no_proof
        rescue StandardError => ex
          OT.le "[CustomDomain.validation_strategy_state] #{ex.class}: #{ex.message}; " \
                'serving requires verified ownership and email domain proof requires a Colonel override'
          :unbuildable
        end
      end
    end
  end
end
