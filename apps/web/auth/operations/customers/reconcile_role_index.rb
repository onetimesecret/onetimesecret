# apps/web/auth/operations/customers/reconcile_role_index.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

module Auth
  module Operations
    module Customers
      # Reconcile the customer role index (customer:role_index:*) against the
      # authoritative `role` field on each customer record (#3974).
      #
      # The ONE implementation of the role-index reconcile verb. The
      # `bin/ots customers role reconcile` command is a thin adapter: it owns
      # CLI concerns (flags, confirmation, output, exit codes) and delegates
      # the check + repair to this op.
      #
      # ## Why the index drifts (familia 2.12)
      #
      # `Customer` declares `multi_index :role, :role_index`. Two mechanisms
      # let the derived index disagree with the `role` field:
      #
      # 1. ADD-ONLY partial writes. In familia 2.12, `save_fields` /
      #    `multi_field_update` / `commit_fields` route multi_index maintenance
      #    through `add_to_class_role_index`, which only ever SADDs into the
      #    NEW value's bucket — stale membership in the previous value's bucket
      #    is intentionally retained on value change. Only the app's full-save
      #    override (lib/onetime/models/customer/features/role_index.rb) does
      #    old-bucket removal, so any role change persisted through a targeted
      #    writer leaves the customer in two buckets.
      #
      # 2. TTL-expired customer hashes. The right-to-be-forgotten feature sets
      #    `default_expiration = 365.days` on the customer hash
      #    (lib/onetime/models/features/right_to_be_forgotten.rb). When the
      #    hash expires, the `customer:role_index:*` set member for it persists
      #    forever — permanently inflating `colonel_count` and `role list`.
      #
      # ## Repair strategy: incremental, never destructive
      #
      # `Customer.rebuild_role_index` (familia-generated) is DEL-then-
      # repopulate: it SCANs and DELs every `customer:role_index:*` key before
      # re-adding members, so a crash mid-run leaves a PARTIAL index (an empty
      # or half-filled bucket that under-reports colonels until the next run).
      # This op instead computes the exact per-bucket diff and applies targeted
      # SADD/SREM operations. Every individual write is a correct repair on its
      # own, so an interrupted run leaves the index strictly closer to correct
      # — never worse than when it started — and a re-run converges.
      #
      # ## Audit (epic #20 CONTRACT 4)
      #
      # A dry run is a pure diagnostic read and records nothing. An applied run
      # that changed the index records ONE ColonelAuditEvent summarizing the
      # additions/removals when an `actor` is supplied. A failed APPLIED run
      # records a failure event on the same gate (Doctor precedent: never audit
      # a failed read-only pass).
      class ReconcileRoleIndex
        include Onetime::LoggerMethods

        AUDIT_VERB = 'customer.role_index_reconcile'

        # How many identifiers to load per LOAD_MULTI batch while building the
        # expected membership map (same default as familia's rebuild).
        BATCH_SIZE = 100

        # @!attribute status [r]
        #   @return [Symbol] :clean (index matches the role fields),
        #     :drift (dry run found divergence; nothing written),
        #     :repaired (applied run wrote the diff)
        # @!attribute scanned [r]
        #   @return [Integer] customer identifiers examined from Customer.instances
        # @!attribute buckets [r]
        #   @return [Hash{String=>Hash}] per-role bucket report:
        #     { 'colonel' => { members: 3, stale: 1, missing: 0 }, ... }.
        #     Includes buckets that exist only in the index (all-stale) and
        #     roles that exist only on customer records (all-missing).
        # @!attribute additions [r]
        #   @return [Array<Hash>] { role:, objid: } members missing from their
        #     role's bucket (SADDed on an applied run)
        # @!attribute removals [r]
        #   @return [Array<Hash>] { role:, objid: } stale members — customer
        #     gone/expired, or its current role differs (SREMed on apply)
        # @!attribute dry_run [r]
        #   @return [Boolean]
        Result = Data.define(:status, :scanned, :buckets, :additions, :removals, :dry_run)

        # @param apply [Boolean] write the SADD/SREM diff when true; default is
        #   a report-only dry run (the safe default — this rewrites index sets
        #   that `role list`, `colonel_count` and `find_first_colonel` read).
        # @param actor [String, #extid, #email, nil] acting admin's PUBLIC
        #   identity (colonel extid, or the CLI sentinel). Only consulted on an
        #   applied run; a dry run records no audit event.
        def initialize(apply: false, actor: nil)
          @apply = apply
          @actor = actor
        end

        # @return [Result]
        def call
          expected, scanned = expected_memberships
          actual            = indexed_memberships

          additions, removals = diff(expected, actual)
          buckets             = bucket_report(expected, actual, additions, removals)

          if additions.empty? && removals.empty?
            return Result.new(
              status: :clean,
              scanned: scanned,
              buckets: buckets,
              additions: additions,
              removals: removals,
              dry_run: !@apply,
            )
          end

          unless @apply
            return Result.new(
              status: :drift,
              scanned: scanned,
              buckets: buckets,
              additions: additions,
              removals: removals,
              dry_run: true,
            )
          end

          apply_diff(additions, removals)
          audit_repair(scanned, additions, removals)

          Result.new(
            status: :repaired,
            scanned: scanned,
            buckets: buckets,
            additions: additions,
            removals: removals,
            dry_run: false,
          )
        rescue StandardError => ex
          # Same gate as Doctor: a failed dry run is a failed READ and must not
          # write an audit event (CONTRACT 4: viewing never writes). A failed
          # APPLIED run may have left part of the diff written — each applied
          # SADD/SREM is individually correct, but the attempt belongs in the
          # trail.
          audit_repair_failure(ex) if @apply && !@actor.nil?
          raise
        end

        private

        # Authoritative state: role field per live customer, built from the
        # class instances collection. A customer whose hash TTL-expired (RTBF)
        # still has its objid in `instances` but loads as nil, so it lands in
        # NO expected bucket — exactly the shape that makes its lingering index
        # member a removal.
        #
        # @return [Array(Hash{String=>Set}, Integer)] role => Set(objid), and
        #   the count of identifiers examined
        def expected_memberships
          expected = Hash.new { |hash, key| hash[key] = Set.new }
          scanned  = 0

          Onetime::Customer.instances.members.each_slice(BATCH_SIZE) do |identifiers|
            scanned += identifiers.size

            Onetime::Customer.load_multi(identifiers).compact.each do |customer|
              role = customer.role.to_s
              next if role.strip.empty?

              expected[role] << customer.identifier.to_s
            end
          end

          [expected, scanned]
        end

        # Current index state, straight from the datastore. SCAN pattern
        # construction mirrors familia's own rebuild_role_index: the namespace
        # prefix comes from class metadata, so the '*' only matches keys under
        # customer:role_index:.
        #
        # @return [Hash{String=>Set}] role => Set(objid) as currently indexed
        def indexed_memberships
          sample  = Onetime::Customer.role_index_for('*')
          pattern = sample.dbkey
          prefix  = pattern.delete_suffix('*')
          client  = Onetime::Customer.dbclient

          actual = {}
          client.scan_each(match: pattern) do |key|
            role         = key.delete_prefix(prefix)
            actual[role] = client.smembers(key).to_set(&:to_s)
          end
          actual
        end

        # @return [Array(Array<Hash>, Array<Hash>)] [additions, removals],
        #   each entry { role:, objid: }, deterministically ordered so reports
        #   and audit details are stable across runs
        def diff(expected, actual)
          roles = (expected.keys | actual.keys).sort

          additions = []
          removals  = []

          roles.each do |role|
            want = expected[role] || Set.new
            have = actual[role] || Set.new

            (want - have).sort.each { |objid| additions << { role: role, objid: objid } }
            (have - want).sort.each { |objid| removals << { role: role, objid: objid } }
          end

          [additions, removals]
        end

        # @return [Hash{String=>Hash}] see Result#buckets
        def bucket_report(expected, actual, additions, removals)
          roles = (expected.keys | actual.keys).sort

          roles.to_h do |role|
            [role, {
              members: (actual[role] || Set.new).size,
              stale: removals.count { |entry| entry[:role] == role },
              missing: additions.count { |entry| entry[:role] == role },
            }]
          end
        end

        # Incremental repair. Additions first: if the run dies partway, the
        # worst intermediate state is the union of both (the same over-report
        # the add-only drift already produces), never a missing colonel.
        # Removing the last member of a set deletes the key server-side, so
        # emptied buckets need no separate cleanup.
        def apply_diff(additions, removals)
          additions.each do |entry|
            Onetime::Customer.role_index_for(entry[:role]).add(entry[:objid])
          end

          removals.each do |entry|
            Onetime::Customer.role_index_for(entry[:role]).remove_element(entry[:objid])
          end
        end

        # One audit event per applied run that changed the index. objid lists
        # are intentionally NOT embedded — a large drift repair would bloat the
        # count-capped audit set; the CLI/report output carries the detail.
        def audit_repair(scanned, additions, removals)
          return if @actor.nil?

          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: 'customer:role_index',
            result: :success,
            detail: {
              scanned: scanned,
              additions: additions.size,
              removals: removals.size,
              roles: (additions + removals).map { |entry| entry[:role] }.uniq.sort,
            },
          )
        end

        # Shared failure-record path (drops authorization rejections, never
        # double-records, best-effort write) — same helper Doctor uses.
        def audit_repair_failure(error)
          Onetime::AuditedFailure.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: 'customer:role_index',
            error: error,
          )
        end
      end
    end
  end
end
