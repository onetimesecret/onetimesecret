# lib/onetime/security/sender_test_email_rate_limiter.rb
#
# frozen_string_literal: true

require 'onetime/security/per_customer_rate_limit'

module Onetime
  module Security
    # SenderTestEmailRateLimiter - Bounds "Send test" on a domain's sender
    #
    # POST /api/domains/:extid/email-config/test (DomainsAPI::Logic::
    # SenderConfig::SendTestEmail) sends a real email through the delivery
    # provider, from the domain's saved sender address, to the acting
    # customer's own address. The endpoint is session-authenticated and
    # limited to the organization owner; what this bounds is VOLUME:
    #
    #   - every send is a real message through the provider, which costs
    #     money and counts against the provider's sending reputation;
    #   - every send writes one `domain_sender.test_email_sent` audit row: an
    #     owner's to the security trail (newest 1,000, 7 days), where an
    #     unbounded loop would push every other row out of the console view;
    #     a colonel's to the operator trail. Both are charged here.
    #
    # Per CUSTOMER, keyed on the public extid: one actor has one budget
    # whatever domain they point it at. Ten per hour covers several
    # change-and-retest cycles while setting up a sender.
    #
    # The mechanics (atomic Lua check-and-record, cap-reaching request
    # allowed, fail-closed on Redis errors, one security-trail event per
    # cap-hit) are {PerCustomerRateLimit}'s; this module declares the policy.
    # Charged from the END of SendTestEmail#raise_concerns — after the
    # session, ownership and entitlement guards and after the saved sender
    # configuration is found — so a refused request costs nothing.
    #
    # CLEARING A STUCK LOCKOUT — the same two paths as every other limiter,
    # over kind `sender_test_email`:
    #
    #   1. `bin/ots ratelimit keys sender_test_email <extid>` piped to
    #      valkey-cli (the CLI only PRINTS commands; see ratelimit_command.rb).
    #   2. `POST /api/colonel/ratelimit/reset` with kind=sender_test_email,
    #      which performs the delete AND records a ColonelAuditEvent.
    #
    # Redis keys (string keys at the Redis boundary; Customer shard):
    #   - sender_test_email:attempts:{extid}  - per-customer send counter
    #   - sender_test_email:locked:{extid}    - per-customer lockout flag
    #
    # Config (features.organizations.sender_test_email_rate_limit): enabled,
    # max_per_customer, window, lockout. Absent config -> enabled with the
    # constant defaults below; set enabled:false to disable (the test config
    # does, so the sender specs are not throttled; the limiter tryout enables
    # it in-process).
    #
    # Usage:
    #   include Onetime::Security::SenderTestEmailRateLimiter
    #   enforce_sender_test_email_rate_limit!(cust.extid)  # last line of raise_concerns
    module SenderTestEmailRateLimiter
      # Test sends permitted per window for one customer.
      DEFAULT_MAX_PER_CUSTOMER = 10

      # Window in seconds over which sends are counted (1 hour).
      DEFAULT_WINDOW = 3600

      # Lockout duration in seconds once the cap is hit (1 hour).
      DEFAULT_LOCKOUT = 3600

      # Audit verb recorded when the bucket reaches its cap, next to the
      # `domain_sender.test_email_sent` verb of each send.
      AUDIT_VERB = 'domain_sender.test_email_throttled'

      # Keep `kind` byte-identical with the 'sender_test_email' row of
      # Onetime::Operations::RateLimit::Registry::LIMITERS.
      POLICY = PerCustomerRateLimit::Policy.new(
        kind: 'sender_test_email',
        config_key: 'sender_test_email_rate_limit',
        default_max_per_customer: DEFAULT_MAX_PER_CUSTOMER,
        default_window: DEFAULT_WINDOW,
        default_lockout: DEFAULT_LOCKOUT,
        audit_verb: AUDIT_VERB,
        message: 'Too many test emails. Please try again later.',
        log_tag: 'SenderTestEmailRateLimiter',
        action_noun: 'sends',
      )

      # Enforce the per-customer send limit and record this send. See
      # {PerCustomerRateLimit.enforce!}.
      #
      # @param customer_extid [String] The acting customer's public id.
      # @raise [ArgumentError] If the subject is blank.
      # @raise [Onetime::LimitExceeded] If the limit is exceeded.
      # @return [void]
      def enforce_sender_test_email_rate_limit!(customer_extid)
        PerCustomerRateLimit.enforce!(POLICY, customer_extid)
      end
    end
  end
end
