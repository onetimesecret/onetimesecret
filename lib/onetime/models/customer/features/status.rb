# lib/onetime/models/customer/features/status.rb
#
# frozen_string_literal: true

require_relative '../../field_types'

module Onetime::Customer::Features
  module Status
    # See InstanceMethods#mark_closure_started!. Returns the stored marker,
    # or nil when the record is gone.
    MARK_CLOSURE_STARTED = <<~LUA
      if redis.call('EXISTS', KEYS[1]) == 0 then return false end
      redis.call('HSETNX', KEYS[1], 'closure_started_at', ARGV[1])
      return redis.call('HGET', KEYS[1], 'closure_started_at')
    LUA

    # A closure runs inside one request and is done in seconds. A marker
    # older than this belongs to a closure that is no longer running, so the
    # tools that act on a marker (the customers doctor, finish-closures) can
    # do so without racing the request that wrote it.
    CLOSURE_STALE_AFTER = 15 * 60

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      # Pull in the BooleanFieldMacro so `boolean_field :verified` becomes
      # available alongside the standard `field` declarations. This is the
      # Familia-idiomatic equivalent of the upstream `encrypted_field`
      # macro: a custom FieldType handles canonicalization at the type
      # level, so callers cannot bypass it via the setter, the fast
      # writer, or by passing the field through Customer.create!.
      base.extend Onetime::Models::FieldTypes::BooleanFieldMacro

      base.field :role
      base.field :joined
      base.boolean_field :verified
      # Provenance tag for how the account became verified; nil when
      # unverified. See Auth::Operations::Customers::Doctor::VALID_VERIFIED_BY
      # for the full list of in-use values and where each is written.
      base.field :verified_by

      # Why an sso_jit customer was left unverified at JIT provisioning; one
      # of Onetime::Customer::VERIFICATION_HOLDS, nil when nothing was
      # withheld (every non-SSO record, SSO records that predate the field,
      # and SSO records that were verified at creation). Set once by the
      # OmniAuth JIT hook via EnsureCustomerForAccount and never rewritten,
      # so the customers doctor can tell a record that drifted (auto-
      # repairable: mirror the Verified accounts row) from one where
      # verification was withheld on purpose (never auto-repaired; an
      # operator verifies by hand once the address is confirmed).
      base.field :verification_hold

      # Reversible trust & safety pause (NOT a role, NOT destructive).
      # A suspended customer keeps all of their data but cannot authenticate:
      # login rejects them and BaseSessionAuthStrategy refuses their sessions.
      # Managed exclusively via the audited SetSuspension op (colonel API);
      # see Auth::Operations::Customers::SetSuspension.
      base.boolean_field :suspended
      base.field :suspended_at      # Unix timestamp when the suspension was applied
      base.field :suspended_by      # acting admin's PUBLIC id (extid), never an objid
      base.field :suspended_reason  # optional operator-supplied reason

      # Account closure in progress or interrupted (#4819). Written by
      # Auth::Operations::TeardownAccount just before it removes the sign-in
      # identity (a self-service closure: by after_close_account, before its
      # purge starts), and deleted with the record when the closure
      # completes. A record that outlives its closure (the
      # Redis deletion failed, or the cleanup stopped part-way, after the
      # SQL identity was removed) keeps it, and `bin/ots customers
      # sync-auth-accounts` refuses to provision a new auth account for it.
      # Unix timestamp; nil on every record no closure has touched.
      base.field :closure_started_at
    end

    module ClassMethods
      # Refuse an unknown verification_hold before anything is written. nil /
      # blank is the stored form of "nothing withheld" and is accepted.
      #
      # @param value [String, Symbol, nil] candidate hold reason
      # @raise [ArgumentError] when value is present and not one of
      #   Onetime::Customer::VERIFICATION_HOLDS
      # @return [void]
      def assert_known_verification_hold!(value)
        return if value.nil? || value.to_s.empty?
        return if Onetime::Customer::VERIFICATION_HOLDS.include?(value.to_s)

        raise ArgumentError,
          "Unknown verification_hold #{value.inspect}; " \
          "expected one of: #{Onetime::Customer::VERIFICATION_HOLDS.keys.join(', ')}"
      end
    end

    module InstanceMethods
      # Stored form is canonical 'true' / 'false' (see
      # Onetime::Models::FieldTypes::BooleanFieldType), so the predicate is a
      # plain string equality check — no truthy-table, no `to_s.downcase`.
      def verified?
        !anonymous? && verified == 'true'
      end

      # Check if account was verified via email confirmation
      def email_verified?
        verified? && verified_by.to_s == 'email'
      end

      # Check if account was created via Stripe payment (not email verified)
      def payment_verified?
        verified? && verified_by.to_s == 'stripe_payment'
      end

      # Was verification deliberately withheld at SSO JIT provisioning?
      # True when verification_hold carries a reason (see
      # Onetime::Customer::VERIFICATION_HOLDS); nil / blank reads as not
      # held. Independent of verified?: an operator who verifies a held
      # record by hand leaves the hold in place as history.
      def verification_held?
        !verification_hold.to_s.empty?
      end

      # Reversible trust & safety pause. Stored form is canonical
      # 'true' / 'false' (BooleanFieldType), so — like verified? — the
      # predicate is a plain string equality check. nil (records that
      # predate the field) reads as not suspended.
      def suspended?
        !anonymous? && suspended == 'true'
      end

      # Has an account closure started for this record? Advisory: no access
      # gate reads it, because a closure that commits deletes the record
      # outright. Provisioning tools do read it, so an interrupted closure
      # is never "repaired" by re-creating the auth account it deleted.
      def closing?
        !closure_started_at.to_s.empty?
      end

      # Closing, and for longer than any closure takes (CLOSURE_STALE_AFTER).
      def closure_stale?(now: Familia.now.to_i)
        closing? && now.to_i - closure_started_at.to_i >= CLOSURE_STALE_AFTER
      end

      # Single-field write, not a save: the teardown is on its way out of the
      # record, and a full save would push stale in-memory state over newer
      # writes. Not the fast writer either: its HSET would recreate a record
      # a concurrent closure deleted in between, as a one-field hash re-added
      # to the instances index, with no expiry. The script writes only while
      # the record exists, and only once, so a closure that resumes keeps the
      # time the first one started.
      #
      # @return [Boolean] false when the record no longer exists
      def mark_closure_started!(at: Familia.now.to_i)
        stored = dbclient.eval(MARK_CLOSURE_STARTED, keys: [dbkey], argv: [serialize_value(at)])
        return false if stored.nil?

        self.closure_started_at = deserialize_value(stored, field_name: :closure_started_at)
        clear_dirty!(:closure_started_at) if respond_to?(:clear_dirty!)
        true
      end

      # For a closure that rolled back: the auth account is open, so the
      # record is live again. HDEL never recreates a deleted record.
      def clear_closure_marker!
        remove_field('closure_started_at')
        self.closure_started_at = nil
        clear_dirty!(:closure_started_at) if respond_to?(:clear_dirty!)
      end

      def active?
        # We modify the role when destroying so if a customer is verified
        # and has a role of 'customer' then they are active. A suspended
        # account is never active: suspension is a reversible trust & safety
        # pause enforced consistently at every access gate (auth strategies,
        # org/workspace behavior), so anything gating on active? honors it too.
        verified? && role?('customer') && !suspended?
      end

      def pending?
        # A customer is considered pending if they are not anonymous, not verified,
        # and have a role of 'customer'. If any one of these conditions is changes
        # then the customer is no longer pending.
        !anonymous? && !verified? && role?('customer') # we modify the role when destroying
      end
    end

    Familia::Base.add_feature self, :status
  end
end
