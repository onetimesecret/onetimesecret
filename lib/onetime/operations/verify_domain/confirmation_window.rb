# lib/onetime/operations/verify_domain/confirmation_window.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    class VerifyDomain
      # Bounds how long an indeterminate TXT check may hold `verified`.
      #
      # An indeterminate check ("could not tell") leaves `verified` alone, so
      # a transient resolver failure never demotes a correctly-configured
      # domain. Left unbounded, that also means a domain whose checks never
      # settle again stays verified forever. This puts a limit on it: once a
      # verified domain has gone MAX_AGE with every check indeterminate, the
      # next indeterminate check withdraws `verified`.
      #
      # Two fields on CustomDomain carry the state:
      #
      #   verified_confirmed_at       epoch of the last passing TXT check
      #   verified_unconfirmed_since  epoch of the first indeterminate check
      #                               since then; nil while there is none
      #
      # The window is measured from verified_unconfirmed_since, not from the
      # last passing check. Deployments that do not run the refresh job may
      # check a domain once in months; measured from the last pass, a single
      # resolver failure on that one check would demote it. Measured from the
      # first indeterminate check, a demotion always takes two indeterminate
      # checks at least MAX_AGE apart with no passing check in between.
      #
      # It follows that a domain with no clock yet (every domain at deploy)
      # starts one on its first indeterminate check and is never demoted by
      # that check.
      #
      # Exempt, exactly as for a definitive failure: a domain held by an
      # operator override. Unverified domains have nothing to withdraw.
      class ConfirmationWindow
        MAX_AGE = 7 * 86_400 # seconds

        attr_reader :unconfirmed_since, :last_confirmed_at, :max_age

        # State is read here, before VerifyDomain writes anything, so
        # expired? keeps its answer after record_unsettled clears the clock.
        #
        # @param domain [Onetime::CustomDomain]
        # @param dns_result [Hash] BaseStrategy#validate_ownership result
        # @param now [Integer] epoch seconds
        # @param max_age [Integer] seconds
        def initialize(domain, dns_result, now: OT.now.to_i, max_age: MAX_AGE)
          @domain            = domain
          @now               = now
          @max_age           = max_age
          @unconfirmed_since = domain.verified_unconfirmed_since
          @last_confirmed_at = domain.verified_confirmed_at
          @applicable        = dns_result[:indeterminate] == true &&
                               domain.verified.to_s == 'true' &&
                               domain.verified_by_override != true
        end

        # The check was indeterminate and the domain has been unconfirmed for
        # longer than max_age.
        def expired?
          @applicable && !unconfirmed_since.nil? && (@now - unconfirmed_since) > max_age
        end

        # A definitive TXT outcome was stored: either answer ends the
        # unconfirmed run, and a pass is the new last confirmation.
        # The caller saves the domain.
        #
        # @param validated [Boolean]
        def record_settled(validated)
          @domain.verified_confirmed_at      = @now if validated
          @domain.verified_unconfirmed_since = nil
        end

        # No definitive outcome was stored. Withdraws `verified` when the
        # window has expired, starts the clock when there is none, and
        # otherwise changes nothing. The caller saves the domain.
        #
        # @return [Boolean] whether `verified` was withdrawn
        def record_unsettled
          return false unless @applicable

          if expired?
            @domain.verified! false
            @domain.verified_unconfirmed_since = nil
            return true
          end

          @domain.verified_unconfirmed_since = @now if unconfirmed_since.nil?
          false
        end
      end
    end
  end
end
