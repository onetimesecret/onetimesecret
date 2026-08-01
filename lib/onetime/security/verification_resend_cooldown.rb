# lib/onetime/security/verification_resend_cooldown.rb
#
# frozen_string_literal: true

module Onetime
  module Security
    # VerificationResendCooldown - per-customer cooldown on duplicate-signup
    # verification resends
    #
    # The signup endpoint (AccountAPI::Logic::Account::CreateAccount) is
    # reachable unauthenticated and deliberately returns the SAME generic
    # success response whether the submitted email is new, an existing
    # verified account, or an existing unverified account (enumeration
    # safety). The existing-unverified branch resends the verification email
    # and — because send_verification_email spawns a fresh receipt pair —
    # ROTATES the customer's reset_secret on every request. Without a
    # cooldown, repeated anonymous POSTs to signup with a known unverified
    # email are (a) a mailbox-spam primitive and (b) a denial primitive:
    # each request invalidates the verification link the victim was just
    # sent, so they can never complete verification while the attacker keeps
    # posting.
    #
    # This module bounds both with a single atomic Redis gate:
    #
    #   SET verification_resend:cooldown:{objid} '1' NX EX <cooldown>
    #
    # The first duplicate signup in a window claims the key and resends;
    # every subsequent one inside the window sees NX fail and SILENTLY skips
    # the resend (info log with obscured email only). The caller still
    # returns the identical generic success response — a throttled request
    # is indistinguishable from an unthrottled one to the client, which is
    # required: any observable difference (status, body, error) would be an
    # account-existence oracle.
    #
    # Keyed on the customer objid, not the submitted string: the branch only
    # runs after find_by_email resolved a real customer, and objid keying
    # means email-case/unicode variants of one account share one bucket.
    #
    # Fail semantics match the other lib/onetime/security/ limiters: Redis
    # errors propagate (fail closed). Here "closed" means the resend is
    # skipped — the surrounding request may 500, but a datastore outage
    # never turns into an unthrottled send path.
    #
    # Accepted residual: the cooldown carries no IP dimension, so an
    # attacker who knows an unverified account exists can keep the denial
    # primitive alive at a slower rate — one resend every cooldown window
    # keeps rotating reset_secret, so the victim's most recent link is
    # still the only valid one and older ones stay dead. The cooldown
    # bounds spam volume and guarantees each link a minimum lifetime; it
    # does not eliminate slow-drip denial. Adding an IP tier is a product
    # decision deferred until it proves necessary.
    #
    # Redis key (string keys at the Redis boundary):
    #   - verification_resend:cooldown:{objid}  - cooldown flag, EX-expired
    #
    # Usage:
    #   include Onetime::Security::VerificationResendCooldown
    #   send_verification_email if claim_verification_resend_slot?(cust)
    module VerificationResendCooldown
      # Seconds between verification resends per customer. Five minutes
      # bounds an attacker to ~12 emails/hour per target and guarantees a
      # verification link stays valid at least this long, while a legitimate
      # user who lost the first email waits at most one coffee-length pause.
      VERIFICATION_RESEND_COOLDOWN = 300

      # Atomically claim this customer's resend slot for the cooldown
      # window. Returns true exactly once per window (SET NX EX); false
      # means a resend already happened recently and the caller must skip
      # sending — silently, preserving the generic success response.
      #
      # @param customer [Onetime::Customer] the resolved existing customer
      # @return [Boolean] true when the resend may proceed
      def claim_verification_resend_slot?(customer)
        key     = "verification_resend:cooldown:#{customer.objid}"
        claimed = verification_resend_redis.set(
          key, '1', nx: true, ex: VERIFICATION_RESEND_COOLDOWN
        )
        unless claimed
          OT.info "[verification-resend-cooldown] Skipping resend for #{customer.obscure_email} (within #{VERIFICATION_RESEND_COOLDOWN}s window)"
        end
        !!claimed
      end

      private

      # Same shard as the customer/auth rate-limit state (matches
      # ResetRequestRateLimiter / LoginRateLimiter).
      def verification_resend_redis
        Onetime::Customer.dbclient
      end
    end
  end
end
