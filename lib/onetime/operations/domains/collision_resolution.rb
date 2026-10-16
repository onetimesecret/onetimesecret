# lib/onetime/operations/domains/collision_resolution.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — see decision D3 in
# lib/onetime/operations/README.md. Loaded at the call site (the CLI
# command), so require what it builds on.
require 'onetime/operations/domains/ascii_index_audit'
require 'onetime/operations/domains/remove'
require 'onetime/operations/domains/collision_sender_preservation'
require 'onetime/operations/admin_verify_domain'
require 'onetime/domain_validation/strategy'
require 'securerandom'
require 'digest'
require_relative 'collision_resolution/record'
require_relative 'collision_resolution/rule'
require_relative 'collision_resolution/plan'
require_relative 'collision_resolution/text'

module Onetime
  module Operations
    module Domains
      # Resolve the collision groups that {AsciiIndexAudit} reports: two
      # or more custom domain records for one DNS name. The backfill never
      # writes them; this operation decides which record to keep by a fixed
      # rule ({Rule}), writes the decision to a plan an operator reviews,
      # and applies the plan. The CLI adapter is
      # `bin/ots domains resolve-collisions`.
      #
      # ## plan
      #
      # Read-only. Runs the audit, gathers the facts the rule reads for every
      # record in a collision group (Record), and decides each group. The
      # Plan serialises to JSON. A manual group has no keep; an operator sets
      # `keep` to the extid of the record to keep and `approved` to true, or
      # `skip` to true.
      #
      # ## apply
      #
      # For every group that is :auto, or :manual with keep and approved:
      #
      #   1. Reject incomplete audits, then preflight all selected groups before
      #      any removal. Compare fresh identity, ownership, use, routing and
      #      billing evidence with the plan; changed groups are skipped.
      #      Check sender identities against every audited record and retain
      #      shared identities, even when both records are planned removals.
      #   2. Remove each other record through {Domains::Remove}, with a
      #      reason naming the kept record, shadows first and the record that
      #      answers for the name last. The provider vhost is keyed by the
      #      name (ApproximatedStrategy#delete_vhost deletes by name), which
      #      the kept record shares, so each removal passes keep_vhost: true
      #      and the vhost stays up throughout. Only a group with no kept
      #      record (all orphans) deletes it.
      #   3. If the name no longer resolves to the kept record, claim the
      #      exact display_domain_index entry for it (a compare-and-set; an
      #      entry another record holds is left alone and reported).
      #   4. On the Approximated strategy, verify the kept record through
      #      {AdminVerifyDomain}, so its stored vhost status is current: a
      #      kept record that never verified has none, and the vhost now
      #      answers for it.
      #
      # The ASCII index is left to `backfill-ascii-index --apply`,
      # which the runbook runs next.
      #
      # ## Run it with the application stopped
      #
      # Same reason as the backfill: nothing here takes a lock shared with
      # domain registration. A plan that matched a running system may not
      # match it a minute later; apply checks, but does not prevent, that.
      #
      # ## Audit trail
      #
      # Every removal and verification records its own ColonelAuditEvent.
      # Each applied/skipped/partial group also records domain.resolve_collision
      # with the reviewed decision and outcomes. A run_id links that summary,
      # the removal reasons, and the full console/JSON evidence report.
      class CollisionResolution
        # One removal within a group.
        #   :removed   Remove ran and committed
        #   :planned   dry run; Remove previewed it
        #   :failed    Remove raised; detail names the error
        #   :removed_audit_failed  deletion committed, but its audit write failed
        Removal = Data.define(:ref, :display_domain, :status, :detail)

        # What apply did with one group.
        #   :applied   every removal landed
        #   :partial   a removal failed, or a kept-record step did
        #   :dry_run   previewed only
        #   :skipped   nothing was done; reason says why
        Outcome = Data.define(:ascii_name, :status, :reason, :keep, :removals, :index_claim, :verify_state, :errors, :context) do
          def initialize(context: {}, **attributes)
            super(**attributes, context: context)
          end

          def skipped?
            status == :skipped
          end

          def to_h
            super.merge(
              status: status.to_s,
              verify_state: verify_state&.to_s,
              index_claim: index_claim&.to_s,
              removals: removals.map { |removal| removal.to_h.merge(status: removal.status.to_s) },
            )
          end
        end

        ApplyResult = Data.define(:dry_run, :strategy, :outcomes) do
          # Whether something needs an operator: a skipped or partial group.
          def attention?
            outcomes.any? { |outcome| [:skipped, :partial].include?(outcome.status) }
          end

          def counts
            outcomes.map { |outcome| outcome.status.to_s }.tally
          end

          def to_h
            { dry_run: dry_run, strategy: strategy, counts: counts, outcomes: outcomes.map(&:to_h) }
          end
        end

        STRATEGIES_WITH_VHOST = ['approximated'].freeze

        # @param audit [AsciiIndexAudit::Result, nil] reuse an audit the
        #   caller already ran
        # @return [Plan]
        def plan(audit: nil)
          @served_ids = {}
          audit     ||= AsciiIndexAudit.new.call
          require_complete_audit!(audit)
          groups      = audit.collision_groups.map do |ascii_name, rows|
            records  = rows.map { |row| record_for(row) }
            decision = Rule.decide(records)
            Group.new(
              ascii_name: ascii_name,
              decision: decision.decision,
              rule: decision.rule,
              keep: ref_of(records, decision.keep),
              remove: decision.remove.map { |id| ref_of(records, id) },
              notes: decision.notes,
              records: records,
              approved: false,
              skip: false,
            )
          end

          Plan.new(
            generated_at: Time.now.utc.iso8601,
            rule_version: Rule::VERSION,
            strategy: strategy_name,
            groups: groups,
          )
        end

        # @param plan [Plan]
        # @param actor [String] public identity for the audit events ('cli')
        # @param dry_run [Boolean] preview without domain changes; removal
        #   previews can write observation audit events
        # @param only [String, nil] apply one group, by its ASCII name
        # @return [ApplyResult]
        # @raise [InvalidPlan] on an incomplete audit, another rule version,
        #   or an `only` that names no group in the plan
        def apply(plan, actor:, dry_run: true, only: nil)
          raise InvalidPlan, 'rule version changed; regenerate and review the plan' unless plan.rule_version == Rule::VERSION

          @served_ids    = {}
          audit          = AsciiIndexAudit.new.call
          require_complete_audit!(audit)
          live           = audit.collision_groups
          groups         = only ? [plan.group!(only)] : plan.groups
          run_id         = SecureRandom.uuid
          started        = Time.now.utc.iso8601
          checksum       = Digest::SHA256.hexdigest(plan.to_json)
          # Finish every selected group's read-only checks before any mutation.
          identity_cache = {}
          preflights     = groups.map do |group|
            preflight(group, live[group.ascii_name], records: audit.rows, identity_cache: identity_cache)
          end
          outcomes       = groups.zip(preflights).map do |group, (reason, sender_preservation)|
            context = {
              run_id: run_id,
              run_started_at: started,
              plan_generated_at: plan.generated_at,
              plan_sha256: checksum,
              rule_version: plan.rule_version,
              decision: group.decision.to_s,
              rule: group.rule.to_s,
              approved: group.approved,
              approval_required: group.approval_required?,
              billing_source: 'local_cache',
              records: group.records.map(&:to_h),
              notes: group.notes,
            }
            outcome = if reason
                        skipped(group, reason).with(context: context)
                      else
                        apply_group(group, sender_preservation, actor: actor, dry_run: dry_run, context: context)
                      end
            dry_run ? outcome : audit_outcome(outcome, actor: actor)
          end

          ApplyResult.new(dry_run: dry_run, strategy: strategy_name, outcomes: outcomes)
        end

        private

        def require_complete_audit!(audit)
          return if audit.errors.empty?

          raise InvalidPlan, "incomplete audit: #{audit.errors.size} unreadable record(s); nothing removed; repair and rerun the audit"
        end

        def model
          Onetime::CustomDomain
        end

        def strategy_name
          Onetime::DomainValidation::Strategy.for_config(OT.conf).strategy_name
        rescue StandardError => ex
          OT.le "[Domains::CollisionResolution] validation strategy unknown: #{ex.class}: #{ex.message}"
          'unknown'
        end

        def ref_of(records, domain_id)
          return nil if domain_id.nil?

          records.find { |record| record.domain_id == domain_id }&.ref || domain_id
        end

        # ----- plan: facts -------------------------------------------------

        def record_for(row)
          record = model.find_by_identifier(row.domain_id)
          raise InvalidPlan, "record #{row.domain_id} disappeared while gathering evidence" unless record

          org    = row.org_id.to_s.empty? ? nil : Onetime::Organization.load(row.org_id)

          Record.new(
            domain_id: row.domain_id,
            extid: row.extid,
            display_domain: row.display_domain,
            org_id: row.org_id,
            org_extid: org&.extid,
            org_name: org&.display_name,
            org_state: org_state_for(org, row.org_id),
            served: served_id(row.ascii_name) == row.domain_id,
            verification_state: row.verification_state,
            ownership_verified: row.ownership_verified == true,
            verified_by_override: row.verified_by_override == true,
            verified_confirmed_at: row.verified_confirmed_at,
            receipts: record ? record.receipts.size.to_i : 0,
            configs: record ? config_kinds(row.domain_id, strong_only: true) : [],
            all_configs: record ? config_kinds(row.domain_id, strong_only: false) : [],
            brand: record ? record.brand.exists? : false,
            vhost: record ? !record.vhost.to_s.empty? : false,
            created: row.created,
            **billing_fields(org),
          )
        end

        def billing_fields(org)
          BILLING_FIELDS.to_h { |field| [field, org&.public_send(field)] }
        end

        # A non-empty org_id that loads nothing is :dangling, not :missing:
        # the record is still an orphan, but the billing facts the removal
        # guard reads are unreadable, so the plan requires approval for it.
        def org_state_for(org, org_id)
          return :missing if org.nil? && org_id.to_s.empty?
          return :dangling if org.nil?

          org.archived? ? :archived : :active
        end

        # The record a request for the name (its A-label, the form on the
        # wire) resolves to.
        def served_id(ascii_name)
          @served_ids                                           ||= {}
          @served_ids.fetch(ascii_name) { @served_ids[ascii_name] = model.display_domain_id_for(ascii_name) }
        end

        def config_kinds(domain_id, strong_only:)
          kinds = Onetime::CustomDomain::ConfigRegistry::KINDS
          kinds = kinds.reject { |_, kind| kind[:materializable] } if strong_only
          kinds.select { |_, kind| kind[:model].exists_for_domain?(domain_id) }.keys
        end

        # ----- apply -------------------------------------------------------

        def preflight(group, live_rows, records:, identity_cache:)
          reason = refusal(group, live_rows)
          return [reason, nil] if reason

          preservation = CollisionSenderPreservation.new(group: group, records: records, identity_cache: identity_cache).call
          removal_records(group, group.keep_record).each do |record|
            value = preservation.fetch(record.domain_id)
            raise InvalidPlan, "unknown sender preservation for #{record.ref}" unless [true, false].include?(value)
          end
          [nil, preservation]
        rescue StandardError => ex
          ["preflight failed: #{ex.class}: #{ex.message}; nothing removed", nil]
        end

        def apply_group(group, sender_preservation, actor:, dry_run:, context:)
          keeper    = group.keep_record
          removals  = removal_records(group, keeper)
          results   = removals.map do |record|
            remove(
              record,
              group,
              keeper,
              actor: actor,
              dry_run: dry_run,
              run_id: context[:run_id],
              keep_sender_identity: sender_preservation.fetch(record.domain_id),
            )
          end
          errors    = []
          claim     = nil
          verified  = nil

          claim, verified = keeper_steps(group, keeper, errors, actor: actor) if keeper && !dry_run
          failed          = results.any? { |removal| [:failed, :removed_audit_failed].include?(removal.status) } || errors.any?
          status          = dry_run ? :dry_run : :applied
          status          = :partial if failed

          Outcome.new(
            ascii_name: group.ascii_name,
            status: status,
            reason: nil,
            keep: keeper&.ref,
            removals: results,
            index_claim: claim,
            verify_state: verified,
            errors: errors,
            context: context,
          )
        end

        # The summary complements (never replaces) each domain.remove event.
        # Keep counts alongside bounded audit arrays; the console/JSON contains
        # every record even when the audit store caps a large group's detail.
        def audit_outcome(outcome, actor:)
          detail = outcome.context.merge(
            keep: outcome.keep,
            status: outcome.status.to_s,
            reason: outcome.reason,
            totals: {
              records: outcome.context[:records].size,
              removals: outcome.removals.size,
              removed: outcome.removals.count { |removal| [:removed, :removed_audit_failed].include?(removal.status) },
              failed: outcome.removals.count { |removal| removal.status == :failed },
              audit_failed: outcome.removals.count { |removal| removal.status == :removed_audit_failed },
            },
            removals: outcome.removals.map(&:to_h),
            index_claim: outcome.index_claim,
            verify_state: outcome.verify_state,
            errors: outcome.errors,
          )
          Onetime::ColonelAuditEvent.record(
            actor: actor,
            verb: 'domain.resolve_collision',
            target: outcome.ascii_name,
            result: outcome.status == :applied ? :success : :failure,
            detail: detail,
            fail_closed: true,
          )
          outcome
        rescue Onetime::AuditWriteFailure => ex
          OT.le "[Domains::CollisionResolution] run=#{outcome.context[:run_id]} audit summary failed for #{outcome.ascii_name}: #{ex.message}"
          outcome.with(status: :partial, errors: outcome.errors + ["Administrator's Log summary failed: #{ex.message}"])
        end

        # Why a group is not applied, or nil.
        def refusal(group, live_rows)
          plan_refusal(group) || live_refusal(group, live_rows)
        end

        # The plan itself: the operator's edits are consistent.
        def plan_refusal(group)
          return 'skipped in the plan' if group.skip
          return 'manual group: set keep and approved in the plan' if group.manual? && !(group.approved && group.keep)
          if group.approval_pending?
            return 'billing-protected removals require approved=true in the reviewed plan (--yes does not approve groups)'
          end
          return "keep #{group.keep} names no record in the group" if group.keep && group.keep_record.nil?
          return 'nothing to remove' if group.keep.nil? && group.records.size == 1

          keeper   = group.keep_record
          expected = (group.records - [keeper].compact).map(&:domain_id).sort
          listed   = group.remove.map { |ref| group.record(ref)&.domain_id }
          return 'remove names a record outside the group' if listed.include?(nil)

          listed.sort!
          return 'remove does not match keep: remove every record but the kept one, or leave it empty' if listed.any? && listed != expected

          nil
        end

        # The datastore: the group still is what the plan saw.
        def live_refusal(group, live_rows)
          return 'no longer a collision group' if live_rows.nil?

          plan_ids = group.records.map(&:domain_id).sort
          return 'the records sharing the name changed since the plan' if live_rows.map(&:domain_id).sort != plan_ids

          fresh = live_rows.map { |row| record_for(row) }
          group.records.each do |record|
            current = fresh.find { |candidate| candidate.domain_id == record.domain_id }
            if current.org_state != record.org_state || current.billing_fingerprint != record.billing_fingerprint
              return "#{record.ref} organization or billing changed since the plan; regenerate and review the plan"
            end
            if current.evidence_fingerprint != record.evidence_fingerprint
              return "#{record.ref} changed since the plan; regenerate and review the plan"
            end
          end
          return 'an empty keeper requires freshly confirmed all-orphans' if group.keep.nil? && !fresh.all?(&:orphan?)

          # The rule never keeps an orphan; only an edited keep can name one.
          # Nothing owns a kept orphan, and the owned records would be removed
          # for it, without approval when their billing does not protect them.
          keeper = group.keep_record && fresh.find { |candidate| candidate.domain_id == group.keep_record.domain_id }
          return "keep #{group.keep} names an orphan (organization #{keeper.org_state}); keep an owned record or skip the group" if keeper&.orphan?

          nil
        rescue StandardError => ex
          "could not recheck organization billing: #{ex.class}: #{ex.message}; nothing removed"
        end

        # Shadows first; the record that answers for the name last, so the
        # exact index entry is empty for the shortest time.
        def removal_records(group, keeper)
          (group.records - [keeper].compact).sort_by { |record| record.served ? 1 : 0 }
        end

        def remove(record, group, keeper, actor:, dry_run:, run_id:, keep_sender_identity: false)
          domain = model.find_by_identifier(record.domain_id)
          return Removal.new(ref: record.ref, display_domain: record.display_domain, status: :failed, detail: 'record not found') unless domain

          reason = "collision run=#{run_id}: kept #{keeper ? keeper.ref : 'none'} by rule #{group.rule}; name=#{group.ascii_name}"
          result = Domains::Remove.new(
            domain: domain,
            actor: actor,
            dry_run: dry_run,
            reason: reason,
            keep_vhost: !keeper.nil?,
            **(keep_sender_identity ? { keep_sender_identity: true } : {}),
          ).call
          Removal.new(
            ref: record.ref,
            display_domain: record.display_domain,
            status: dry_run ? :planned : :removed,
            detail: result.reasserts_survivor ? 'exact index entry re-asserted for the survivor' : nil,
          )
        rescue Domains::Remove::RemovalCommitted => ex
          Removal.new(ref: record.ref, display_domain: record.display_domain, status: :removed, detail: ex.message)
        rescue Onetime::AuditWriteFailure => ex
          # Remove writes its own fail-closed success event only AFTER teardown.
          # Do not turn an unrecorded, committed deletion into a claimed failure
          # to delete. Failures from a different nested verb make no such claim.
          status = ex.verb == Domains::Remove::AUDIT_VERB && !dry_run ? :removed_audit_failed : :failed
          Removal.new(ref: record.ref, display_domain: record.display_domain, status: status, detail: ex.message)
        rescue StandardError => ex
          OT.le "[Domains::CollisionResolution] removing #{record.ref} (#{group.ascii_name}) raised #{ex.class}: #{ex.message}"
          Removal.new(ref: record.ref, display_domain: record.display_domain, status: :failed, detail: "#{ex.class}: #{ex.message}")
        end

        # @return [Array(Symbol, nil), Array(Symbol, nil)] index claim outcome
        #   (:created, :already_held, :refused, nil when not needed) and the
        #   verification state (nil when the strategy has no vhost)
        def keeper_steps(group, keeper, errors, actor:)
          domain = model.find_by_identifier(keeper.domain_id)
          unless domain
            errors << "kept record #{keeper.ref} not found after the removals"
            return [nil, nil]
          end

          [claim_exact_entry(group, domain, errors), verify_keeper(domain, errors, actor: actor)]
        rescue StandardError => ex
          errors << "reloading kept record #{keeper.ref} raised #{ex.class}: #{ex.message}"
          [nil, nil]
        end

        def claim_exact_entry(group, domain, errors)
          return nil if model.display_domain_id_for(group.ascii_name) == domain.identifier

          outcome = model.display_domain_index.claim_field(domain.display_domain.to_s, domain.identifier)
          case outcome
          when :created
            OT.info "[Domains::CollisionResolution] Claimed display_domain_index[#{domain.display_domain}] for #{domain.identifier}"
            :created
          when :owned then :already_held
          else
            errors << "display_domain_index[#{domain.display_domain}] names #{outcome}; not claimed for #{domain.identifier}"
            :refused
          end
        rescue StandardError => ex
          errors << "claiming display_domain_index[#{domain.display_domain}] raised #{ex.class}: #{ex.message}"
          :refused
        end

        def verify_keeper(domain, errors, actor:)
          return nil unless STRATEGIES_WITH_VHOST.include?(strategy_name)

          result = Onetime::Operations::AdminVerifyDomain.new(domain: domain, actor: actor, persist: true).call
          errors << "verifying #{domain.extid} failed: #{result.error}" unless result.error.nil?
          errors << "verification for #{domain.extid} was not persisted" unless result.persisted == true
          result.current_state
        rescue StandardError => ex
          errors << "verifying #{domain.extid} raised #{ex.class}: #{ex.message}"
          nil
        end

        def skipped(group, reason)
          Outcome.new(
            ascii_name: group.ascii_name,
            status: :skipped,
            reason: reason,
            keep: group.keep,
            removals: [],
            index_claim: nil,
            verify_state: nil,
            errors: [],
          )
        end
      end
    end
  end
end
