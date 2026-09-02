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
      # ## Concurrency posture: revalidate at apply, converge on rerun
      #
      # The customer scan and the index scan are separate, non-atomic reads, so
      # a role change/creation/deletion that lands between snapshot and apply
      # can make a diff entry stale. An applied run therefore REVALIDATES each
      # entry immediately before writing it: the customer is freshly reloaded
      # and the write is skipped (and reported in Result#skipped) when the
      # entry's premise no longer holds. A single fresh read per entry is
      # deliberate — no WATCH/MULTI across the whole run; the tiny remaining
      # window between an entry's revalidation and its SADD/SREM is accepted,
      # and a rerun (which skipped entries exit non-cleanly into anyway)
      # converges on it.
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
        #     role's bucket. On a dry run: the full detected set. On an applied
        #     run: only the entries actually SADDed (stale ones move to skipped).
        # @!attribute removals [r]
        #   @return [Array<Hash>] { role:, objid: } stale members — customer
        #     gone/expired, or its current role differs. On an applied run: only
        #     the entries actually SREMed (stale ones move to skipped).
        # @!attribute skipped [r]
        #   @return [Array<Hash>] { role:, objid:, action:, reason: } diff
        #     entries whose premise no longer held at apply-time revalidation
        #     (a concurrent role change/creation/deletion overlapped the run);
        #     nothing was written for them. Always empty on a dry run. A rerun
        #     re-evaluates them from fresh snapshots.
        # @!attribute dry_run [r]
        #   @return [Boolean]
        Result = Data.define(:status, :scanned, :buckets, :additions, :removals, :skipped, :dry_run)

        # @param apply [Boolean] write the SADD/SREM diff when true; default is
        #   a report-only dry run (the safe default — this rewrites index sets
        #   that `role list`, `colonel_count` and `find_first_colonel` read).
        # @param actor [String, #extid, #email, nil] acting admin's PUBLIC
        #   identity (colonel extid, or the CLI sentinel). An applied run
        #   records to the operator trail; a dry run records one `preview`
        #   observation (#4337). Both are skipped when the actor is unknown.
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
            record_preview_event(:clean, scanned, additions, removals) unless @apply
            return Result.new(
              status: :clean,
              scanned: scanned,
              buckets: buckets,
              additions: additions,
              removals: removals,
              skipped: [],
              dry_run: !@apply,
            )
          end

          unless @apply
            record_preview_event(:drift, scanned, additions, removals)
            return Result.new(
              status: :drift,
              scanned: scanned,
              buckets: buckets,
              additions: additions,
              removals: removals,
              skipped: [],
              dry_run: true,
            )
          end

          applied_additions, applied_removals, skipped = apply_diff(additions, removals)

          # Diff fully written: from here on, a raise (e.g. in the audit write)
          # must not be recorded as a repair failure.
          repair_written = true
          audit_repair(scanned, applied_additions, applied_removals, skipped)

          Result.new(
            status: :repaired,
            scanned: scanned,
            buckets: buckets,
            additions: applied_additions,
            removals: applied_removals,
            skipped: skipped,
            dry_run: false,
          )
        rescue StandardError => ex
          # Same gate as Doctor: a failed dry run is a failed READ and must not
          # write a FAILURE event — nothing was attempted, so there is no
          # attempt to record (the successful-preview observation above is a
          # different thing, and it is on a different trail). A failed
          # APPLIED run may have left part of the diff written — each applied
          # SADD/SREM is individually correct, but the attempt belongs in the
          # trail. Once the diff is fully written, though, a failure in the
          # audit write itself must NOT record a failure event — the repair
          # succeeded, and a `:failure` entry for a run that fixed the index
          # would poison the trail (the exception still propagates so the CLI
          # surfaces it).
          audit_repair_failure(ex) if @apply && !@actor.nil? && !repair_written
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
        #
        # Each entry is REVALIDATED against a fresh read of its customer
        # immediately before the write, because the diff was computed from
        # snapshots that a concurrent role change/creation/deletion may have
        # invalidated. A write whose premise no longer holds is skipped and
        # reported instead of applied. A mutation can still land between an
        # entry's fresh read and its SADD/SREM — that residual per-entry window
        # is accepted; a rerun converges on it.
        #
        # @return [Array(Array<Hash>, Array<Hash>, Array<Hash>)]
        #   [applied_additions, applied_removals, skipped]
        def apply_diff(additions, removals)
          skipped = []

          applied_additions = additions.select do |entry|
            current = current_role(entry[:objid])
            if current == entry[:role]
              Onetime::Customer.role_index_for(entry[:role]).add(entry[:objid])
              true
            else
              skipped << entry.merge(
                action: :add,
                reason: "customer role is now #{current.nil? ? '(gone)' : current.inspect}",
              )
              false
            end
          end

          applied_removals = removals.select do |entry|
            current = current_role(entry[:objid])
            if current == entry[:role]
              skipped << entry.merge(
                action: :remove,
                reason: 'customer now holds this role again',
              )
              false
            else
              Onetime::Customer.role_index_for(entry[:role]).remove_element(entry[:objid])
              true
            end
          end

          [applied_additions, applied_removals, skipped]
        end

        # Fresh, non-batched read of the customer's current role, bypassing the
        # snapshot the diff was computed from.
        #
        # @return [String, nil] the role, or nil when the customer hash is
        #   gone/expired or the role field is blank (no bucket membership is
        #   correct for either)
        def current_role(objid)
          customer = Onetime::Customer.load(objid)
          role     = customer&.role.to_s
          role.strip.empty? ? nil : role
        end

        # One audit event per applied run that changed the index. objid lists
        # are intentionally NOT embedded — a large drift repair would bloat the
        # count-capped audit set; the CLI/report output carries the detail.
        def audit_repair(scanned, additions, removals, skipped)
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
              skipped: skipped.size,
              roles: (additions + removals + skipped).map { |entry| entry[:role] }.uniq.sort,
            },
          )
        end

        # One OBSERVATION per dry run (#4337), on the budgeted access trail.
        #
        # A report-only run walks EVERY live customer's role and reports the
        # index drift — a whole-install read, and the safe default this op
        # ships with, so it was the path that left no trace at all.
        #
        # Gated on a known actor, like {audit_repair}: this op is reachable
        # from tooling that passes `actor: nil` (the doctor path), and an
        # observation attributed to nobody is noise rather than accountability
        # (ADR-023 — never fabricate an actor). Counts only, for the same
        # reason the applied event carries counts: an objid list would bloat a
        # capped set.
        def record_preview_event(status, scanned, additions, removals)
          return if @actor.nil?

          Onetime::ColonelAuditEvent.record_access(
            actor: @actor,
            verb: AUDIT_VERB,
            target: 'customer:role_index',
            result: 'preview',
            detail: {
              dry_run: true,
              status: status.to_s,
              scanned: scanned,
              additions: additions.size,
              removals: removals.size,
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
