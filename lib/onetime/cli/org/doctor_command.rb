# lib/onetime/cli/org/doctor_command.rb
#
# frozen_string_literal: true

# Check and repair organization data integrity issues.
#
# Performs the following integrity checks:
#   1. owner_id points to an existing customer
#   2. owner_id customer is in the members sorted set
#   3. All members in sorted set have backing customer objects
#   4. Membership role:'owner' records match org's owner_id
#   5. Organization has at least one member
#   6. stripe_customer_id has a unique-index entry pointing back at this org
#
# --all additionally sweeps organization:stripe_customer_id_index for entries
# no live organization carries (see sweep_stripe_customer_id_index).
#
# --repair on check 1 promotes a member with role:'owner', writing owner_id as
# the objid (#3907). When the stored created_by is that same person's legacy
# custid/email, created_by is migrated to objid space alongside it; a
# DIFFERENT person's created_by is never touched (transfer-style audit state,
# D32).
#
# --repair on check 6 handles the two MECHANICAL index states (missing entry,
# stale entry), and writes them with a compare-and-set against the value the
# diagnosis was made from, so a claim that landed in between (a Stripe webhook,
# an `org reconcile`) is never erased. Two live orgs carrying one Stripe
# customer id is a billing decision, not a data repair — it is reported with
# both sides' context and never auto-fixed (#4205).
#
# Usage:
#   bin/ots org doctor on8q30gih2uxu2cw77jzh7caq07     # Check single org
#   bin/ots org doctor --all                            # Scan all orgs
#   bin/ots org doctor --all --repair                   # Auto-repair issues
#   bin/ots org doctor on8q... --json                   # JSON output

require 'json'
# Org::Shared must exist before `include Org::Shared` below. Required here (not
# only from the lib/onetime/cli.rb manifest) so this file cannot be loaded in a
# broken order.
require_relative 'shared'

module Onetime
  module CLI
    # rubocop:disable Metrics/ClassLength
    class OrgDoctorCommand < Command
      # Shared org resolution (extid first, objid fallback) + error_exit +
      # org_label. Doctor used to carry a private load_org; the two org commands
      # must not drift on how an ORG argument resolves.
      include Org::Shared

      desc 'Check organization data integrity'

      argument :extid,
        type: :string,
        required: false,
        desc: 'Organization extid or objid (omit for --all scan)'

      option :all,
        type: :boolean,
        default: false,
        desc: 'Scan all organizations'

      option :repair,
        type: :boolean,
        default: false,
        desc: 'Auto-repair issues (default: audit only)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output'

      # Severity levels for issue reporting
      SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, warning: 3, low: 4 }.freeze

      # Compare-and-set / compare-and-delete on ONE field of a class-level
      # unique index, run atomically by Redis. Same shape as the index release
      # in Customers::ChangeEmail (RELEASE_INDEX_CLAIM_SCRIPT) and the
      # :state_cas feature: eval against index.dbkey through index.dbclient.
      #
      # --repair reads the index, classifies, and then writes. Between those
      # steps a Stripe webhook or an `org reconcile` can complete a full save
      # and claim the very field being repaired. A blind HSET/HDEL would erase
      # that valid claim and re-open the lockout this check exists to close, so
      # every write states the value it was decided against and stands down if
      # the entry has moved.
      #
      # The expected value is the RAW bytes read from Redis, not the stripped
      # form used for classification: a legacy JSON-encoded entry ("\"on1a…\"")
      # would otherwise never match, and the repair would report a race that is
      # not one. Redis yields a Lua false for a missing field, hence the
      # explicit absent-or-empty test for a claim on an unheld id.
      #
      # KEYS[1] index key, ARGV[1] field, ARGV[2] expected value, ARGV[3] the
      # value to write. Returns 1 to the caller that performs the write.
      INDEX_CAS_SCRIPT = <<~LUA
        local current = redis.call('HGET', KEYS[1], ARGV[1])
        if current == ARGV[2] or (current == false and ARGV[2] == '') then
          redis.call('HSET', KEYS[1], ARGV[1], ARGV[3])
          return 1
        end
        return 0
      LUA

      INDEX_CAD_SCRIPT = <<~LUA
        local current = redis.call('HGET', KEYS[1], ARGV[1])
        if current == ARGV[2] then
          redis.call('HDEL', KEYS[1], ARGV[1])
          return 1
        end
        return 0
      LUA

      def call(extid: nil, all: false, repair: false, json: false, **)
        boot_application!

        unless extid || all
          show_usage
          return
        end

        orgs   = all ? scan_all_orgs : [resolve_org(extid, json: json)]
        report = { checked: 0, healthy: 0, issues: [], repaired: [] }

        # Before any check: which live orgs carry which Stripe customer id.
        # Check 6 needs the whole picture to refuse to pick a winner (#4205).
        # --all has it by construction; a single-org run starts with a map of
        # one and completes it lazily, only where drift turns up (see
        # #ensure_stripe_customer_claims).
        index_stripe_customer_claims(orgs)
        @stripe_claims_complete = all

        orgs.each do |org|
          next unless org

          check_org(org, report, repair: repair)
        end

        # --all only: the sweep skips Stripe customer ids a live org still
        # carries, and the claim map backing that skip covers exactly the orgs
        # passed in above. On a single-org run it would name every other org's
        # entry an orphan — and with --repair, delete them.
        sweep_stripe_customer_id_index(report, repair: repair) if all

        output_report(report, json: json, repair: repair)

        # Exit with error if issues found
        exit_with_status(report, repair: repair)
      end

      def exit_with_status(report, repair:)
        return if report[:issues].empty?

        # Collect all issues to check repairability
        all_issues     = report[:issues].flat_map { |org| org[:issues] }
        has_repairable = all_issues.any? { |i| i[:repairable] }

        if repair
          # In repair mode: error if nothing was repaired but issues exist
          if report[:repaired].empty?
            if has_repairable
              # Repairable issues exist but repair failed
              exit 1
            else
              # No repairable issues - inform user and exit with error
              puts
              puts 'ERROR: --repair specified but no issues are auto-repairable.'
              puts 'Manual intervention required.'
              exit 2
            end
          end
          # Some repairs succeeded - exit success even if some issues remain
        else
          # Audit mode: exit with error code to indicate issues found
          exit 1
        end
      end

      private

      def show_usage
        puts <<~USAGE
          Usage: bin/ots org doctor [EXTID] [options]

          Check organization data integrity and optionally repair issues.

          Arguments:
            EXTID                   Organization extid to check (optional if --all)

          Options:
            --all                   Scan all organizations
            --repair                Auto-repair issues (default: audit only)
            --json                  JSON output

          Examples:
            bin/ots org doctor on8q30gih2uxu2cw77jzh7caq07
            bin/ots org doctor --all
            bin/ots org doctor --all --repair

          Checks performed:
            1. owner_id points to existing customer (CRITICAL)
            2. owner_id customer is in members set (HIGH)
            3. All members have backing customer objects (MEDIUM)
            4. Membership role:'owner' matches owner_id (WARNING)
            5. Organization has at least one member (WARNING)
            6. stripe_customer_id unique-index entry (CRITICAL/HIGH/MEDIUM)

          With --all, organization:stripe_customer_id_index is also swept for
          entries no live organization carries (MEDIUM, repairable).

          Two LIVE organizations carrying the same Stripe customer id is
          reported, never auto-repaired: decide which org the Stripe customer
          belongs to, clear the stripe_* fields on the other, then run
            bin/ots org reconcile ORG
        USAGE
      end

      def scan_all_orgs
        orgs = []
        Onetime::Organization.instances.each do |objid|
          org = Onetime::Organization.load(objid)
          orgs << org if org
        end
        orgs
      end

      def check_org(org, report, repair:)
        report[:checked] += 1
        issues            = []

        # CHECK 1: owner_id -> existing customer
        check_owner_exists(org, issues, report, repair: repair)

        # CHECK 2: owner in members set (only if owner exists)
        check_owner_in_members(org, issues, report, repair: repair)

        # CHECK 3: members have backing objects
        check_members_exist(org, issues, report, repair: repair)

        # CHECK 4: membership role sync
        check_membership_role_sync(org, issues)

        # CHECK 5: has members
        check_has_members(org, issues)

        # CHECK 6: stripe_customer_id unique-index integrity
        check_stripe_customer_id_index(org, issues, report, repair: repair)

        if issues.empty?
          report[:healthy] += 1
        else
          report[:issues] << {
            org_extid: org.extid,
            org_objid: org.objid,
            display_name: org.display_name,
            issues: issues.sort_by { |i| SEVERITY_ORDER[i[:severity]] },
          }
        end
      end

      def check_owner_exists(org, issues, report, repair:)
        return if org.owner_id.to_s.empty?

        owner_customer = Onetime::Customer.load(org.owner_id)
        return if owner_customer

        # Find potential repair candidate (member with role:'owner')
        candidate = find_owner_candidate(org)

        issue = {
          check: :owner_exists,
          severity: :critical,
          message: "owner_id '#{org.owner_id}' points to deleted customer",
          repairable: !candidate.nil?,
        }

        if candidate
          issue[:repair_action] = "Will promote #{candidate[:extid]} (#{candidate[:email]}) as new owner"
          issue[:candidate]     = candidate
        else
          issue[:repair_action] = 'No eligible candidate found (no member with role:owner)'
        end

        issues << issue

        return unless repair

        if candidate
          # Actually perform the promotion
          promoted = promote_owner_from_membership(org)
          if promoted
            report[:repaired] << {
              org: org.extid,
              action: :owner_promoted,
              new_owner_custid: promoted[:custid],
              new_owner_extid: promoted[:extid],
              # true when created_by held the promoted owner's own legacy
              # custid/email and was migrated to objid space alongside
              # owner_id (same person, new encoding — see
              # same_person_created_by?)
              created_by_migrated: promoted[:created_by_migrated],
            }
          end
        else
          OT.info "[org doctor] Could not auto-repair #{org.extid}: no eligible owner candidate"
        end
      end

      def check_owner_in_members(org, issues, report, repair:)
        return if org.owner_id.to_s.empty?

        owner_customer = Onetime::Customer.load(org.owner_id)
        return unless owner_customer # Already flagged by check_owner_exists
        return if org.member?(owner_customer)

        issues << {
          check: :owner_in_members,
          severity: :high,
          message: "owner '#{org.owner_id}' not in members set",
          repairable: true,
        }

        return unless repair

        # Add owner to members set with proper membership record
        org.add_members_instance(owner_customer)
        ensure_membership_record(org, owner_customer, role: 'owner')
        report[:repaired] << { org: org.extid, action: :owner_added_to_members }
      end

      def check_members_exist(org, issues, report, repair:)
        stale_members = find_stale_members(org)
        return if stale_members.empty?

        issues << {
          check: :members_exist,
          severity: :medium,
          message: "#{stale_members.size} stale member(s) in set",
          stale_ids: stale_members,
          repairable: true,
        }

        return unless repair

        remove_stale_members(org, stale_members)
        report[:repaired] << {
          org: org.extid,
          action: :stale_members_removed,
          count: stale_members.size,
        }
      end

      def check_membership_role_sync(org, issues)
        role_mismatches = find_role_mismatches(org)
        return if role_mismatches.empty?

        issues << {
          check: :membership_role_sync,
          severity: :warning,
          message: "#{role_mismatches.size} membership(s) with role:'owner' but custid != owner_id",
          mismatches: role_mismatches,
          repairable: false, # requires manual decision
        }
      end

      def check_has_members(org, issues)
        return if org.member_count.positive?

        issues << {
          check: :has_members,
          severity: :warning,
          message: 'organization has no members',
          repairable: false,
        }
      end

      # CHECK 6: stripe_customer_id unique-index integrity (#4205)
      #
      # Organization declares `unique_index :stripe_customer_id,
      # :stripe_customer_id_index` (with_organization_billing.rb). Familia
      # claims that class-level index on every FULL save through a server-side
      # CAS, so an entry mapping this org's Stripe customer id to a DIFFERENT
      # objid makes every subsequent full save raise:
      #
      #   Key already exists: Onetime::Organization exists
      #   stripe_customer_id=cus_XXX (existing_id=<current holder>)
      #
      # That is a silent lockout, not a cosmetic one — Stripe webhook updates,
      # `org reconcile`, and entitlement materialization all take the full-save
      # path — and nothing surfaces it until something tries to write. Three
      # drift states, only two of them mechanical:
      #
      #   missing entry   the field was written without claiming the index — a
      #                   Familia fast write, or a write inside MULTI; neither
      #                   can maintain a class-level index. No lockout yet: the
      #                   id reads as unclaimed, so ANOTHER org can take it and
      #                   lock this one out. Repair: claim it.
      #   stale entry     the entry points at an objid that no longer loads, or
      #                   at an org that has since moved to a different Stripe
      #                   customer. Nobody contests the id; this org is locked
      #                   out by a dead pointer. Repair: repoint it here.
      #   duplicate       another LIVE org carries the same Stripe customer id.
      #                   Report-only, ALWAYS: choosing the canonical org means
      #                   reading which org the Stripe customer's subscription
      #                   actually references, and the loser needs its stripe_*
      #                   fields cleared by a human.
      #
      # The duplicate test comes FIRST and does not depend on where the index
      # points. An index entry aimed at a third, deleted objid while two live
      # orgs both carry the id is otherwise indistinguishable from a plain
      # stale entry — and --repair would then award the customer to whichever
      # org the scan happened to reach first.
      #
      # Nothing is reported or repaired from a partial claim map. A single-org
      # run knows only about that org and whoever the index names, which cannot
      # tell a missing entry apart from two orgs contesting an unheld id — so
      # the moment an org shows drift, the map is completed first
      # (#ensure_stripe_customer_claims). A healthy org returns before that,
      # which keeps the scan off the common path.
      #
      # Stripe, not this index, is the source of truth about who owns the
      # customer; the doctor's job is to say so, not to choose.
      def check_stripe_customer_id_index(org, issues, report, repair:)
        return unless org.respond_to?(:stripe_customer_id)

        # VERBATIM, not stripped: Familia keys the index field on the field
        # value exactly as stored, so a lookup on a trimmed copy would miss the
        # real entry and --repair would then write a SECOND field for the same
        # Stripe customer. Only the emptiness test tolerates whitespace.
        customer_id = org.stripe_customer_id.to_s
        return if customer_id.strip.empty?

        index = stripe_customer_id_index
        return if index.nil?

        # Kept side by side: the RAW bytes Redis holds, which the repair CAS
        # has to expect, and the stripped form everything else compares.
        raw_holder   = raw_index_value(index, customer_id)
        holder_objid = index_value(raw_holder)
        mine         = org.objid.to_s

        # The only path that costs nothing extra, and the common one: this org
        # holds its own entry and nothing already known contests it. Every line
        # below is about to report or repair, and neither may be decided from a
        # partial claim map.
        return if holder_objid == mine && live_rivals(org, customer_id, holder_objid).empty?

        ensure_stripe_customer_claims
        rivals = live_rivals(org, customer_id, holder_objid)

        if rivals.any?
          issues << duplicate_index_issue(org, customer_id, holder_objid, rivals)
          return # never auto-repaired, in either direction
        end

        return if holder_objid == mine # healthy: org holds its own entry

        issue = if holder_objid.empty?
                  missing_index_issue(org, customer_id)
                else
                  stale_index_issue(org, customer_id, holder_objid)
                end

        issues << issue

        return unless repair

        repair_index_entry(org, index, issue, report,
          customer_id: customer_id, raw_holder: raw_holder, holder_objid: holder_objid)
      end

      # The repair write. Compare-and-set against the value the classification
      # above was made from (see INDEX_CAS_SCRIPT): if a concurrent full save
      # settled the entry in the meantime, that claim is left standing.
      #
      # Losing the CAS is not a failure to report as one — somebody else's
      # write has already done the job, or has made a different call this run
      # is no longer entitled to override. It is recorded on the issue so the
      # operator can see the entry moved, and the next run reads settled state.
      def repair_index_entry(org, index, issue, report, customer_id:, raw_holder:, holder_objid:)
        unless claim_index_entry(index, customer_id, raw_holder, org.objid)
          issue[:repair_skipped] = 'index entry changed while doctor was running; re-run to see the settled state'
          OT.info "[org doctor] stripe_customer_id_index[#{customer_id}] moved under repair; left as found"
          return
        end

        OT.info "[org doctor] stripe_customer_id_index[#{customer_id}] -> #{org.objid} (was #{holder_objid.inspect})"
        report[:repaired] << {
          org: org.extid,
          action: issue[:state] == :missing_entry ? :stripe_index_claimed : :stripe_index_repointed,
          stripe_customer_id: customer_id,
          previous_objid: holder_objid.empty? ? nil : holder_objid,
        }
      end

      # Complete the claim map before check 6 acts on anything.
      #
      # A single-org run cannot otherwise distinguish "no org has claimed this
      # id" from "two orgs carry it and neither holds the entry" — and --repair
      # would then claim the id for whichever org was named on the command
      # line, quietly picking the winner of a duplicate that is never supposed
      # to be auto-repaired.
      #
      # Lazy and memoised: --all arrives complete, and a single-org run only
      # reaches here once its org already shows drift. The O(all orgs) walk is
      # paid exactly where a wrong answer would be written to Redis.
      def ensure_stripe_customer_claims
        return if @stripe_claims_complete

        index_stripe_customer_claims(scan_all_orgs)
        @stripe_claims_complete = true
      end

      # Compare-and-set one index field. True iff THIS caller wrote it.
      def claim_index_entry(index, field, expected_raw, objid)
        index.dbclient.eval(
          INDEX_CAS_SCRIPT,
          keys: [index.dbkey],
          argv: [field.to_s, expected_raw.to_s, objid.to_s],
        ).to_i == 1
      end

      # Compare-and-delete one index field. True iff THIS caller removed it.
      def release_index_entry(index, field, expected_raw)
        index.dbclient.eval(
          INDEX_CAD_SCRIPT,
          keys: [index.dbkey],
          argv: [field.to_s, expected_raw.to_s],
        ).to_i == 1
      end

      # Live organizations OTHER than this one that carry the same Stripe
      # customer id: whoever the claim map knows about, plus whoever the index
      # names. Only as complete as the map it is called with — which is why
      # every caller that goes on to report or repair calls
      # #ensure_stripe_customer_claims first.
      #
      # An org is only a rival if it still carries the id — an index entry
      # pointing at an org that has since moved on is a stale pointer, not a
      # competing claim.
      def live_rivals(org, customer_id, holder_objid)
        objids = stripe_customer_claims[customer_id].to_a.dup
        objids << holder_objid unless holder_objid.empty?
        objids = objids.uniq - [org.objid.to_s]

        objids.filter_map do |objid|
          rival = Onetime::Organization.load(objid)
          next unless rival
          next unless rival.stripe_customer_id.to_s == customer_id

          rival
        end
      end

      def missing_index_issue(org, customer_id)
        {
          check: :stripe_customer_id_index,
          state: :missing_entry,
          severity: :medium,
          message: "stripe_customer_id '#{customer_id}' has no index entry (unclaimed: another org can take it)",
          stripe_customer_id: customer_id,
          index_objid: nil,
          repairable: true,
          repair_action: "Will claim #{customer_id} for #{org.extid}",
        }
      end

      def stale_index_issue(org, customer_id, holder_objid)
        {
          check: :stripe_customer_id_index,
          state: :stale_entry,
          severity: :high,
          message: "stripe_customer_id '#{customer_id}' index entry #{stale_index_reason(holder_objid)}; " \
                   'every full save on this org fails until repaired',
          stripe_customer_id: customer_id,
          index_objid: holder_objid,
          repairable: true,
          repair_action: "Will repoint #{customer_id} to #{org.extid}",
        }
      end

      # Only called once live_rivals has come back empty, so the holder either
      # does not load or has moved to a different Stripe customer.
      def stale_index_reason(holder_objid)
        holder = Onetime::Organization.load(holder_objid)
        return "points at deleted org '#{holder_objid}'" if holder.nil?

        "points at #{holder.extid}, which now carries #{holder.stripe_customer_id.to_s.inspect}"
      end

      def duplicate_index_issue(org, customer_id, holder_objid, rivals)
        {
          check: :stripe_customer_id_index,
          state: :duplicate,
          severity: :critical,
          message: "stripe_customer_id '#{customer_id}' is carried by #{rivals.size + 1} live organizations " \
                   "(also: #{rivals.map(&:extid).join(', ')}); #{duplicate_consequence(org, holder_objid)}",
          stripe_customer_id: customer_id,
          index_objid: holder_objid.empty? ? nil : holder_objid,
          holds_index: holder_objid == org.objid.to_s,
          contender: org_billing_context(org, holder_objid),
          rivals: rivals.map { |rival| org_billing_context(rival, holder_objid) },
          repairable: false,
          repair_action: 'Manual: confirm in Stripe which org the customer belongs to, clear the stripe_* ' \
                         'fields on the other, then run `bin/ots org reconcile` on the survivor',
        }
      end

      # Which side of a duplicate is actually locked out depends on where the
      # index points — say it plainly rather than making the operator infer it.
      def duplicate_consequence(org, holder_objid)
        return 'the others cannot complete a full save' if holder_objid == org.objid.to_s
        return 'the first of them to save claims the id and locks out the rest' if holder_objid.empty?

        'this org cannot complete a full save'
      end

      # SWEEP: index entries no live organization carries
      #
      # Check 6 walks organizations, so it can only ever see Stripe customer
      # ids some org still holds in its field. An entry left behind by a
      # deleted org is invisible to it — and it silently BLOCKS whichever org
      # tries to claim that customer id next. --all only (see #call).
      def sweep_stripe_customer_id_index(report, repair:)
        index = stripe_customer_id_index
        return if index.nil?

        orphans = collect_orphan_index_entries(index)
        return if orphans.empty?

        report[:issues] << {
          type: :stripe_customer_id_index,
          label: 'organization:stripe_customer_id_index',
          issues: [{
            check: :stripe_customer_id_index_orphans,
            severity: :medium,
            message: "#{orphans.size} index entr#{orphans.size == 1 ? 'y' : 'ies'} " \
                     'no live organization carries',
            orphan_entries: orphans.first(10),
            total_orphans: orphans.size,
            repairable: true,
            repair_action: 'Will remove the orphaned entries, freeing those Stripe customer ids',
          }],
        }

        return unless repair

        removed = remove_orphan_index_entries(index, orphans)
        return if removed.zero?

        report[:repaired] << {
          action: :stripe_index_orphans_removed,
          count: removed,
          skipped: orphans.size - removed,
        }
      end

      # Delete each orphan by compare-and-delete against the value seen when it
      # was classified (see INDEX_CAD_SCRIPT), never by field name alone.
      #
      # Classification and deletion are separate round trips, and an orphan is
      # by definition a Stripe customer id nobody holds — precisely the id a
      # billing webhook or an `org reconcile` is free to claim in between. A
      # blind HDEL there would delete a valid, seconds-old claim, leaving the
      # billed org unindexed and its id open for another org to take.
      #
      # @return [Integer] entries actually removed.
      def remove_orphan_index_entries(index, orphans)
        orphans.count do |entry|
          field = entry[:stripe_customer_id]

          if release_index_entry(index, field, entry[:raw_value])
            OT.info "[org doctor] Removed orphaned stripe_customer_id_index[#{field}]"
            true
          else
            OT.info "[org doctor] stripe_customer_id_index[#{field}] was claimed since the scan; left alone"
            false
          end
        end
      end

      def collect_orphan_index_entries(index)
        orphans = []

        # HGETALL rather than HSCAN: a sweep that DELETES needs exactly-once
        # semantics (HSCAN may yield a field twice under a concurrent rehash),
        # and this hash is bounded by the organizations that have ever had a
        # Stripe customer — a population --all has already loaded one by one.
        # Through the raw client, for the reason #raw_index_value gives.
        index.dbclient.hgetall(index.dbkey).each do |customer_id, raw_objid|
          # A live org carries this id: whatever is wrong with the entry is
          # check 6's finding, reported against that org. Skipping here keeps
          # one defect from being counted twice and — the part that matters —
          # stops --repair from deleting an entry check 6 just claimed.
          next if stripe_customer_claims.key?(customer_id)

          objid  = index_value(raw_objid)
          holder = objid.empty? ? nil : Onetime::Organization.load(objid)

          # raw_value is what the compare-and-delete expects back: the bytes
          # this classification was made from, legacy encoding and all.
          if holder.nil?
            orphans << {
              stripe_customer_id: customer_id,
              objid: objid,
              raw_value: raw_objid,
              reason: 'organization not found',
            }
          elsif holder.stripe_customer_id.to_s != customer_id
            orphans << {
              stripe_customer_id: customer_id,
              objid: objid,
              raw_value: raw_objid,
              reason: "org #{holder.extid} carries #{holder.stripe_customer_id.to_s.inspect}",
            }
          end
        end

        orphans
      end

      # Pre-pass over the orgs about to be checked: Stripe customer id =>
      # objids of the live orgs carrying it.
      #
      # Built BEFORE any check runs, and that ordering is load-bearing. Check 6
      # has to know about a second live claimant even when the index points at
      # neither org, or --repair would hand the customer to whichever org the
      # scan reached first and report nothing. A --all run sees every org; a
      # single-org run sees only that org plus whoever the index names, which
      # is the most a single-org run can know.
      def index_stripe_customer_claims(orgs)
        orgs.each do |org|
          next unless org
          next unless org.respond_to?(:stripe_customer_id)

          customer_id = org.stripe_customer_id.to_s
          next if customer_id.strip.empty?

          # Idempotent: a single-org run indexes its org up front and may then
          # re-cover it in the lazy full scan (#ensure_stripe_customer_claims).
          claims = (stripe_customer_claims[customer_id] ||= [])
          claims << org.objid.to_s unless claims.include?(org.objid.to_s)
        end
      end

      # The class-level Familia HashKey behind `unique_index
      # :stripe_customer_id`. nil when the billing feature is not loaded, which
      # makes check 6 and the sweep no-ops rather than a NoMethodError.
      def stripe_customer_id_index
        return nil unless Onetime::Organization.respond_to?(:stripe_customer_id_index)

        Onetime::Organization.stripe_customer_id_index
      end

      # Stripe customer id => Array<objid>, filled in by
      # #index_stripe_customer_claims. Lazy so the sweep and check 6 can be
      # driven directly (specs, tryouts) without a full scan having run.
      def stripe_customer_claims
        @stripe_customer_claims ||= {}
      end

      # Read one index field through the raw client, bypassing Familia.
      #
      # Familia 2.10.1 strips a legacy JSON-encoded value on the way out, so a
      # value read through the index object is not what Redis holds. A
      # compare-and-set has to state the bytes actually stored or it can never
      # match a legacy entry — so the read that feeds one cannot be the read
      # that rewrites it. The 20260606_01_unique_index_json_to_raw migration
      # goes around Familia for the same reason. #index_value strips afterwards,
      # for classification only.
      def raw_index_value(index, field)
        index.dbclient.hget(index.dbkey, field.to_s)
      end

      # Familia 2.9 stored unique-index values JSON-encoded ("\"on1a…\"");
      # 2.10+ stores them raw. Reads here come from the raw client
      # (#raw_index_value), so the legacy form arrives intact and has to be
      # stripped before anything is compared: an unstripped value reads as a
      # conflict, and with --repair would hand a live org's entry to somebody
      # else. Stripped the same way Familia's read path does. (Storage is
      # rewritten for good by the 20260606_01_unique_index_json_to_raw
      # migration.)
      def index_value(raw)
        value = raw.to_s
        return value unless Familia.respond_to?(:legacy_json_encoded?)
        return value unless Familia.legacy_json_encoded?(value)

        value[1..-2].to_s
      end

      # Enough of an org for a human to adjudicate a duplicate without going
      # and looking both of them up. Emails are OBSCURED, matching how check 1
      # renders a repair candidate.
      def org_billing_context(org, holder_objid)
        {
          extid: org.extid,
          objid: org.objid,
          display_name: org.display_name,
          planid: org.planid,
          subscription_status: org.subscription_status,
          stripe_subscription_id: org.stripe_subscription_id,
          holds_index: org.objid.to_s == holder_objid,
          owner: owner_context(org),
        }
      end

      # nil when the owner is missing or unloadable — itself a check 1 finding,
      # so it is reported there rather than raised from here.
      def owner_context(org)
        owner = org.owner
        return nil unless owner

        { extid: owner.extid, email: owner.obscure_email }
      rescue StandardError
        nil
      end

      # Repair helpers

      def find_owner_candidate(org)
        # Find a member with role:'owner' who could be promoted (read-only check)
        org.members.to_a.each do |member_id|
          membership = find_membership(org.objid, member_id)
          next unless membership
          next unless membership.role == 'owner'

          customer = Onetime::Customer.load(member_id)
          next unless customer # skip if this owner candidate is also deleted

          return {
            custid: customer.custid,
            extid: customer.extid,
            email: customer.obscure_email,
          }
        end
        nil
      end

      def promote_owner_from_membership(org)
        # Find a member with role:'owner' in their membership record
        org.members.to_a.each do |member_id|
          membership = find_membership(org.objid, member_id)
          next unless membership
          next unless membership.role == 'owner'

          customer = Onetime::Customer.load(member_id)
          next unless customer # skip if this owner candidate is also deleted

          # Same-person space migration (#3907): when the stored created_by is
          # this candidate's LEGACY identity (email-shaped custid or email),
          # creator and promoted owner are the same person — carry created_by
          # into the objid space alongside owner_id. Otherwise the repaired org
          # lands in the standardize_owner_id chore's Branch 3b forever, with
          # the legacy email left in a safe-dumped field. A DIFFERENT person's
          # created_by is transfer-style audit state (D32): never touch it.
          migrate_created_by = same_person_created_by?(org, customer)
          org.created_by     = customer.objid if migrate_created_by

          # Update org.owner_id — the OBJID, matching what Organization.create!
          # writes and what check 4 compares against the members set (#3907)
          org.owner_id = customer.objid
          unless org.save
            OT.le "[org doctor] Failed to save org #{org.extid} after owner promotion"
            next
          end
          OT.info "[org doctor] Promoted #{customer.extid} as owner of #{org.extid}"
          return {
            custid: customer.custid,
            extid: customer.extid,
            created_by_migrated: migrate_created_by,
          }
        end
        nil
      end

      # True when org.created_by stores this customer's own legacy identity
      # (custid or email) rather than a different person's id or an objid
      # already in the right space. Gates a SPACE migration only — ADR-012
      # immutability is about WHO created the org, not which key encoding
      # recorded them.
      def same_person_created_by?(org, customer)
        created_by = org.created_by.to_s
        return false if created_by.empty?
        return false if created_by == customer.objid.to_s # already objid space

        [customer.custid.to_s, customer.email.to_s].include?(created_by)
      end

      def ensure_membership_record(org, customer, role:)
        membership = Onetime::OrganizationMembership.ensure_membership(org, customer, role: role)
        OT.info "[org doctor] Ensured membership for #{customer.extid} in #{org.extid} with role:#{role}"
        membership
      end

      def find_stale_members(org)
        stale = []
        org.members.to_a.each do |member_id|
          exists = Familia.dbclient.exists?("customer:#{member_id}:object")
          stale << member_id unless exists
        end
        stale
      end

      def remove_stale_members(org, stale_ids)
        redis = Familia.dbclient
        stale_ids.each do |member_id|
          # Remove from sorted set using raw Redis ZREM (we have string ID, not Customer object)
          redis.zrem(org.members.dbkey, member_id)

          # Clean up orphan membership record if exists
          membership_key = membership_key(org.objid, member_id)
          redis.del(membership_key)

          OT.info "[org doctor] Removed stale member #{member_id} from #{org.extid}"
        end
      end

      def find_role_mismatches(org)
        mismatches = []
        org.members.to_a.each do |member_id|
          membership = find_membership(org.objid, member_id)
          next unless membership
          next unless membership.role == 'owner'
          next if member_id == org.owner_id # correct: this IS the owner

          mismatches << {
            member_id: member_id,
            membership_role: 'owner',
            org_owner_id: org.owner_id,
          }
        end
        mismatches
      end

      def find_membership(org_objid, customer_objid)
        Onetime::OrganizationMembership.find_by_org_customer(org_objid, customer_objid)
      end

      # Build the Redis key for a membership record (used for cleanup of orphans)
      def membership_key(org_objid, customer_objid)
        "org_membership:organization:#{org_objid}:customer:#{customer_objid}:org_membership:object"
      end

      # Output helpers

      def output_report(report, json:, repair:)
        if json
          output_json(report)
        else
          output_text(report, repair: repair)
        end
      end

      def output_json(report)
        puts JSON.pretty_generate(report)
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def output_text(report, repair:)
        puts 'Organization Health Check'
        puts '=' * 40
        puts

        puts "Checked: #{report[:checked]}"
        puts "Healthy: #{report[:healthy]}"
        puts "Issues:  #{report[:issues].size}"
        puts

        if report[:repaired].any?
          puts 'Repaired:'
          report[:repaired].each do |r|
            case r[:action]
            when :owner_promoted
              puts "  #{r[:org]}: promoted #{r[:new_owner_extid]} as new owner"
            when :owner_added_to_members
              puts "  #{r[:org]}: added owner to members set"
            when :stale_members_removed
              puts "  #{r[:org]}: removed #{r[:count]} stale member(s)"
            when :stripe_index_claimed
              puts "  #{r[:org]}: claimed stripe_customer_id_index[#{r[:stripe_customer_id]}]"
            when :stripe_index_repointed
              puts "  #{r[:org]}: repointed stripe_customer_id_index[#{r[:stripe_customer_id]}] " \
                   "(was #{r[:previous_objid]})"
            when :stripe_index_orphans_removed
              puts "  removed #{r[:count]} orphaned stripe_customer_id_index entr#{r[:count] == 1 ? 'y' : 'ies'}"
              puts "  left #{r[:skipped]} alone (claimed since the scan)" if r[:skipped].to_i.positive?
            else
              puts "  #{r[:org]}: #{r[:action]}"
            end
          end
          puts
        end

        return if report[:issues].empty?

        puts 'Issues Found:'
        puts '-' * 40

        report[:issues].each do |org_issues|
          puts
          puts issue_group_header(org_issues)

          org_issues[:issues].each do |issue|
            severity_label = severity_tag(issue[:severity])
            repairable     = issue[:repairable] ? '' : ' [manual fix required]'
            puts "  #{severity_label} #{issue[:message]}#{repairable}"

            # Show repair action hint for repairable issues
            if issue[:repair_action]
              puts "             #{issue[:repair_action]}"
            end

            print_issue_details(issue)
          end
        end

        return if repair

        # Only suggest --repair if there are repairable issues
        all_issues     = report[:issues].flat_map { |org| org[:issues] }
        has_repairable = all_issues.any? { |i| i[:repairable] }

        puts
        puts '-' * 40
        if has_repairable
          puts 'To auto-repair repairable issues, run with --repair'
        else
          puts 'All issues require manual intervention.'
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      # Most groups are one organization. The check-6 index sweep is a
      # class-level group with no org to name, so it labels itself.
      def issue_group_header(group)
        return group[:label].to_s if group[:org_extid].nil?

        "#{group[:org_extid]} (#{group[:display_name]})"
      end

      # Per-issue detail lines. Each block is independent — an issue carrying
      # two detail shapes prints both (the old inline version bailed out of the
      # loop before the second could render).
      def print_issue_details(issue)
        if issue[:stale_ids]
          issue[:stale_ids].first(5).each { |id| puts "    - #{id}" }
          print_truncation(issue[:stale_ids].size, 5)
        end

        if issue[:mismatches]
          issue[:mismatches].first(3).each do |m|
            puts "    - member #{m[:member_id]} has role:'owner' but owner_id=#{m[:org_owner_id]}"
          end
          print_truncation(issue[:mismatches].size, 3)
        end

        if issue[:orphan_entries]
          issue[:orphan_entries].each do |entry|
            puts "    - #{entry[:stripe_customer_id]} -> #{entry[:objid]} (#{entry[:reason]})"
          end
          print_truncation(issue[:total_orphans].to_i, issue[:orphan_entries].size)
        end

        print_duplicate_detail(issue) if issue[:state] == :duplicate

        puts "    ! #{issue[:repair_skipped]}" if issue[:repair_skipped]
      end

      def print_truncation(total, shown)
        remaining = total - shown
        puts "    ... and #{remaining} more" if remaining.positive?
      end

      # The duplicate is the one check-6 state a human has to adjudicate, so
      # print every claimant here rather than making the operator look them up.
      def print_duplicate_detail(issue)
        ([issue[:contender]] + issue[:rivals].to_a).compact.each do |context|
          owner = context[:owner]
          puts "    - #{context[:extid]} (#{context[:display_name]})#{context[:holds_index] ? ' [holds index entry]' : ''}"
          puts "        planid=#{context[:planid].inspect} " \
               "subscription_status=#{context[:subscription_status].inspect} " \
               "stripe_subscription_id=#{context[:stripe_subscription_id].inspect}"
          puts "        owner=#{owner ? "#{owner[:extid]} #{owner[:email]}" : '(unresolved)'}"
        end
        puts "    - index entry: #{issue[:stripe_customer_id]} -> #{issue[:index_objid] || '(none)'}"
      end

      def severity_tag(severity)
        case severity
        when :critical then '[CRITICAL]'
        when :high     then '[HIGH]    '
        when :medium   then '[MEDIUM]  '
        when :warning  then '[WARNING] '
        when :low      then '[LOW]     '
        else                '[UNKNOWN] '
        end
      end
    end
    # rubocop:enable Metrics/ClassLength

    register 'org doctor', OrgDoctorCommand
  end
end
