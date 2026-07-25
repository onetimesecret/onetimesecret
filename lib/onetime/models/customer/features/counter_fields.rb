# lib/onetime/models/customer/features/counter_fields.rb
#
# frozen_string_literal: true

module Onetime::Customer::Features
  module CounterFields
    Familia::Base.add_feature self, :counter_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.include InstanceMethods
      base.extend ClassMethods

      # Store counters for each customer as separate keys. This allows for simple
      # math operations for aggregation and integrity checks, and avoids the need
      # for complex Lua scripts or loading entire hashkeys to manage hashkey fields.
      #
      # NOTE: Due to a limitation in Familia v2.1 declaring a field group for
      # related fields (i.e. separate db keys) does not work as expected. The
      # named group is empty. No runtime issues though so leaving it so it'll
      # just start working properly when the fix makes it in upstream.
      base.field_group :counters do
        base.counter :secrets_created
        base.counter :secrets_burned
        base.counter :secrets_shared
        base.counter :emails_sent

        # secrets_active — the number of *live* (non-expired, non-revealed)
        # secrets this customer currently owns. This backs the colonel users
        # list's `secrets_count` (issue #60), replacing the former per-request
        # `secret:*` SCAN (10k-capped, undercounted large owners — #2211's
        # blocking-enumeration family of problems).
        #
        # It is incremented once per secret create at the single chokepoint
        # (Onetime::Customer.increment_secrets_active, called from
        # Onetime::Receipt.spawn_pair) and decremented once per early
        # destruction at the mirror chokepoint (decrement_secrets_active,
        # called from Secret#destroy! — reveal, burn, and admin delete all
        # funnel through it). The remaining drift source is TTL expiry, where
        # Redis drops the key silently and no application code runs, so the
        # counter can still OVER-count between reconciliations. Correctness is
        # restored by the daily SET-recount reconciliation
        # (SecretCountReconcileJob) which recomputes each owner's true live
        # count off the request path and resets this counter. That
        # reconciliation remains the primary correctness mechanism; the
        # increment/decrement pair keeps the value approximately fresh between
        # nightly recounts. See #60.
        base.counter :secrets_active
      end

      base.class_counter :secrets_created
      base.class_counter :secrets_shared
      base.class_counter :secrets_burned
      base.class_counter :emails_sent
    end

    # Newest-first cap on the per-owner `secrets` index (Customer#secrets).
    # The index exists to answer "which secrets does this customer own" for the
    # colonel detail view, which renders one bounded page — it is not an
    # archive. Trimming on write means the key size is bounded by construction
    # rather than by hoping expiry keeps up, and readers stay honest by
    # reporting truncation instead of a silently short list.
    SECRET_INDEX_LIMIT = 1_000

    module ClassMethods
      # Increment a customer's per-customer live-secret counter (secrets_active)
      # by object id, without loading the full Customer record.
      #
      # Called from the single secret-creation chokepoint
      # (Onetime::Receipt.spawn_pair). Anonymous / ownerless secrets carry a nil
      # or 'anon' owner_id and are skipped — there is no per-customer counter to
      # bump for them (mirroring the old SCAN, which grouped by a real owner_id).
      #
      # A bare `Customer.new(objid:)` is intentional: constructing the instance
      # does not touch the datastore, and reaching through the `secrets_active`
      # counter issues a single INCR on `customer:<objid>:secrets_active` — the
      # same key the reconciliation resets and the colonel list reads. See #60.
      #
      # When `secret_id` is supplied the owner's `secrets` sorted-set index is
      # maintained in the SAME call, so the "how many" counter and the "which
      # ones" index are written at one chokepoint and can only drift together.
      # The index backs the colonel customer-detail view, which previously had
      # to walk the entire `secret:*:object` keyspace to answer the same
      # question. Callers that pass no secret_id (tests, the nightly
      # reconciliation's callers) keep the pre-index behaviour exactly.
      #
      # @param owner_id [String, nil] the secret owner's Customer objid
      # @param secret_id [String, nil] the created secret's objid; when present,
      #   added to the owner's `secrets` index
      # @param score [Numeric, nil] index score (defaults to now); pass the
      #   secret's `created` so the index orders by creation time
      # @return [void]
      def increment_secrets_active(owner_id, secret_id: nil, score: nil)
        oid = owner_id.to_s
        return if oid.empty? || oid == 'anon'

        cust = new(objid: oid)
        # A bare Customer.new(objid:) is "dirty" (the initializer runs the objid
        # setter), and SortedSet writes warn/raise on a dirty parent. Nothing
        # here is a deferred scalar write, so clear the flag rather than trip a
        # false unsaved-parent diagnostic.
        cust.clear_dirty!
        cust.secrets_active.increment
        index_secret(cust, secret_id, score)
      rescue StandardError => ex
        # A counter bump must never break secret creation. Log and move on; the
        # nightly reconciliation will correct any missed increment.
        OT.le "[increment_secrets_active] #{ex.class}: #{ex.message} (owner_id=#{oid})"
      end

      # Decrement a customer's per-customer live-secret counter (secrets_active)
      # by object id — the mirror of {increment_secrets_active}, called from the
      # single early-destruction chokepoint (Onetime::Secret#destroy!, which
      # reveal, burn, and the colonel delete all funnel through). Keeps the
      # colonel users list's `secrets_count` in step with the live secrets the
      # user-detail view scans, instead of drifting until the nightly recount.
      #
      # Floored at zero: a decrement can race the nightly reconciliation or
      # follow a create that predates the counter's backfill, and a negative
      # "live secrets" count is never meaningful. The floor is applied by
      # undoing ONLY our own over-decrement with a compensating INCR — never by
      # SETting the whole counter to 0. A blanket reset(0) is a non-atomic
      # read-modify-write that would clobber any create's INCR that raced
      # between our DECR and the write, forcing a false zero on an owner who
      # still has live secrets. The compensating INCR touches only the single
      # unit we removed, so concurrent increments survive and the counter never
      # loses live-secret information; reconciliation still SETs the truth daily.
      #
      # @param owner_id [String, nil] the secret owner's Customer objid
      # @param secret_id [String, nil] the destroyed secret's objid; when
      #   present, removed from the owner's `secrets` index so index and
      #   counter move together
      # @return [void]
      def decrement_secrets_active(owner_id, secret_id: nil)
        oid = owner_id.to_s
        return if oid.empty? || oid == 'anon'

        cust    = new(objid: oid)
        cust.clear_dirty! # see increment_secrets_active
        counter = cust.secrets_active
        counter.increment if counter.decrement.negative?
        unindex_secret(cust, secret_id)
      rescue StandardError => ex
        # A counter bump must never break secret destruction. Log and move on;
        # the nightly reconciliation will correct any missed decrement.
        OT.le "[decrement_secrets_active] #{ex.class}: #{ex.message} (owner_id=#{oid})"
      end

      private

      # Add a secret to its owner's newest-first index and trim to
      # SECRET_INDEX_LIMIT. ZADD + ZREMRANGEBYRANK are both O(log n); the trim
      # is what keeps the key bounded without a sweeper job.
      def index_secret(cust, secret_id, score)
        sid = secret_id.to_s
        return if sid.empty?

        cust.secrets.add(sid, (score || Familia.now).to_f)
        # Drop everything outside the newest SECRET_INDEX_LIMIT (lowest scores
        # rank first, so the excess sits at the head). Bare constant on purpose:
        # it resolves lexically, so a namespace move can't turn this into a
        # NameError — which the caller's `rescue StandardError` would swallow
        # (logged via OT.le, never raised), stopping the trim indefinitely
        # while secret creation kept reporting success.
        cust.secrets.remrangebyrank(0, -(SECRET_INDEX_LIMIT + 1))
      end

      # Mirror of {index_secret} — drop the member on early destruction.
      def unindex_secret(cust, secret_id)
        sid = secret_id.to_s
        return if sid.empty?

        cust.secrets.remove_element(sid)
      end
    end

    module InstanceMethods
      def init_counter_fields
        # Initialze auto-increment fields. We do this since Redis
        # gets grumpy about trying to increment a hashkey field
        # that doesn't have any value at all yet. This is in
        # contrast to the regular INCR command where a
        # non-existant key will simply be set to 1.
        self.secrets_created ||= 0
        self.secrets_burned  ||= 0
        self.secrets_shared  ||= 0
        self.emails_sent     ||= 0
        self.secrets_active  ||= 0
      end
    end
  end
end
