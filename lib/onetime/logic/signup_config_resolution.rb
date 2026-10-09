# lib/onetime/logic/signup_config_resolution.rb
#
# frozen_string_literal: true

module Onetime
  module Logic
    # Shared domain-level SignupConfig lookup and autoverify resolution.
    #
    # Includers must provide:
    #   - #signup_config_display_domain  → String or nil
    #   - #signup_config_domain_strategy → env['onetime.domain_strategy'] for
    #     this request (Symbol/String/nil). Only consulted on the read-failure
    #     path; see #signup_config_domain_strategy below for what the default
    #     costs you.
    #   - #signup_config_auth_setting(key) → the value of auth.{key} from site config
    #   - #signup_config_custom_domain_lookup (optional) → the request's
    #     Onetime::CustomDomain::Lookup, so the policy is read against the
    #     record the request already resolved (#4220)
    module SignupConfigResolution
      private

      # AUTOVERIFY IS A POLICY READ TOO (#4157). It reaches the same two
      # datastore reads as the gate, so it inherits the same fail-closed rule
      # rather than a softer one: falling back to the global autoverify setting
      # on a host whose tenant config is unreadable auto-verifies accounts on a
      # custom domain whose owner never opted into that — a widen, in the same
      # direction and for the same reason as the gate's.
      #
      # This never fires ahead of the gate in practice: POST
      # /auth/create-account (the only route reaching CreateAccount) runs
      # Core::Controllers::Base#signup_enabled? first, and that raises on the
      # same read. So the raise here is a backstop for any future caller that
      # resolves autoverify without passing the gate, not the primary defense.
      def resolve_autoverify
        config = domain_signup_config
        return config.autoverify? if config&.enabled?

        signup_config_auth_setting('autoverify').to_s == 'true'
      end

      # The tenant's SignupConfig for the request host, or nil when the host has
      # none (including every operator host).
      #
      # Guarded at the READ, not at each gate, for the same reason the sign-in
      # side is (Core::Controllers::Base#signin_policy_read_failed!): both
      # reads here are policy reads, and #signup_enabled? plus
      # #resolve_autoverify both go through them, so a rescue in one caller
      # would leave the other crashing as an unhandled 500.
      #
      # @raise [Onetime::SignupPolicyUnavailable] on a non-operator host whose
      #   policy could not be read
      def domain_signup_config
        dd = signup_config_display_domain
        return unless dd

        custom_domain = signup_config_lookup_for(dd).record!
        return unless custom_domain

        Onetime::CustomDomain::SignupConfig.find_by_domain_id(custom_domain.identifier)
      rescue Redis::BaseError => ex
        signup_policy_read_failed!(ex)
      end

      # The CustomDomain lookup for +host+: the request's shared lookup
      # (#4220) when the includer has one for that host, otherwise one read
      # of its own, unpublished. #record! on the result re-raises a failed
      # read, so the rescue in #domain_signup_config sees the same
      # Redis::BaseError it saw from CustomDomain.from_display_domain.
      #
      # @param host [String]
      # @return [Onetime::CustomDomain::Lookup]
      def signup_config_lookup_for(host)
        lookup = signup_config_custom_domain_lookup
        return lookup if lookup.is_a?(Onetime::CustomDomain::Lookup) && lookup.host.to_s.casecmp?(host.to_s)

        Onetime::CustomDomain::Lookup.read(host)
      end

      # Optional hook: the request's shared CustomDomain lookup. A
      # request-scoped includer overrides this (Core::Controllers::Base reads
      # it from the Rack env, CreateAccount from the strategy metadata) so the
      # sign-up policy is read against the record the request already
      # resolved. The default reads the display domain itself.
      #
      # @return [Onetime::CustomDomain::Lookup, nil]
      def signup_config_custom_domain_lookup
        nil
      end

      # The per-domain sign-up policy could not be read. Logged here, DECIDED
      # by the model (SignupConfig.resolve_lookup_failure) so this mixin, the
      # sign-in gate and any future consumer share one rule about which hosts
      # survive an unreadable policy instead of each re-deriving it.
      #
      # @raise [Onetime::SignupPolicyUnavailable] on any non-operator host
      # @return [nil] on an operator host
      def signup_policy_read_failed!(exception)
        OT.le "[signup] Sign-up policy lookup failed host=#{signup_config_display_domain} #{exception.class}"

        Onetime::CustomDomain::SignupConfig.resolve_lookup_failure(
          domain_strategy: signup_config_domain_strategy,
        )
      end

      # Default classification for an includer that does not supply one: nil,
      # which operator_host? rejects, so the read-failure path fails CLOSED for
      # such a caller on every host — including the canonical one. That is the
      # safe direction to be wrong in (a 503 during a datastore outage, never a
      # widen), but it is over-strict, so a request-scoped includer should
      # override this with the request's real classification. Both current
      # includers do: Core::Controllers::Base reads env['onetime.domain_strategy']
      # and AccountAPI::Logic::Account::CreateAccount reads the same value off
      # Onetime::Logic::Base#domain_strategy.
      def signup_config_domain_strategy
        nil
      end
    end
  end
end
