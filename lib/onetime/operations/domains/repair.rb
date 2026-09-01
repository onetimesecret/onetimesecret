# lib/onetime/operations/domains/repair.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — see decision D3 in
# lib/onetime/operations/README.md. Lives alongside the incumbent domain ops in
# lib/onetime/operations, under the Domains:: namespace. Loaded at the call site
# (colonel logic + CLI), so require the audit model explicitly, mirroring
# AdminVerifyDomain.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

module Onetime
  module Operations
    module Domains
      # Repair a custom domain's organization relationship — the SINGLE
      # implementation of the repair verb (epic #43 / D3 / CONTRACT 4). Fixes the
      # two relationship inconsistencies the CLI's `bin/ots domains repair` detects:
      #
      #   1. ORPHANED: `org_id` is blank. Repairable only when a target org is
      #      supplied; the op assigns it and adds the domain to the org's collection.
      #   2. NOT-IN-COLLECTION: `org_id` is set and the org exists, but the domain is
      #      missing from that org's `domains` collection. The op adds it.
      #
      # A blank `org_id` with no target org (`:needs_org`) or an `org_id` pointing at
      # a missing org (`:org_not_found`) is BLOCKED — reported, not mutated.
      #
      # ## Dry-run + exactly-once audit (CONTRACT 4)
      #
      # `dry_run: true` (the safe default) computes the plan — the issues found and
      # what would change — and mutates NOTHING and audits NOTHING. `dry_run: false`
      # applies the repairs and records EXACTLY ONE {Onetime::ColonelAuditEvent} per
      # successful mutation. A run that finds no issues (`:no_issues`) or is blocked
      # mutates nothing and records no audit event (the "only audit an actual
      # change" rule).
      #
      # ## Behavioural parity note (latent CLI bug fixed)
      #
      # The incumbent CLI passed `domain.domainid` (a String) to
      # `org.add_domain` / compared it against `org.list_domains` (which returns
      # domain OBJECTS). Those never matched an object collection, so the
      # collection-membership check and add were effectively broken. This op uses
      # the OBJECT-based calls verified by the model tryouts
      # (`org.add_domain(domain)`, `org.list_domains.map(&:domainid)`), which is the
      # intended, correct behaviour. See wiringInstructions / blockers.
      class Repair
        include Onetime::AuditedFailure

        # Audit verb recorded for every applied repair.
        AUDIT_VERB = 'domain.repair'

        # A repair was asked for and could NOT be done. `:no_issues` is not a
        # refusal (the domain is already consistent — the repair succeeded by
        # having nothing to do) and neither is `:planned` (a dry run attempts
        # nothing).
        REFUSAL_STATUSES = [:needs_org, :org_not_found].freeze

        # Each repair lambda writes org_id + saves + mutates the org's domain
        # collection, and `repairs.map(&:call)` runs them all BEFORE the success
        # record — so a repair that blows up on the second of two leaves the
        # domain half-repaired with no trace. Records one `result: :failure` and
        # re-raises.
        #
        # `dry_run` is in the detail because it defaults to TRUE and the success
        # event is applied-path-only.
        #
        # ## Why the UNCONDITIONAL macro is safe here, unlike Customers::Doctor
        #
        # This op has a FLEET-WIDE driver (`bin/ots domains doctor --all
        # --repair` → doctor_command.rb#apply_membership_repair, once per
        # affected domain), which is exactly the shape that made an
        # unconditional wrapper wrong for {Auth::Operations::Customers::Doctor}:
        # there, failure events would have been emitted per customer on a purely
        # DIAGNOSTIC sweep, and the count-capped audit set has no TTL, so a
        # systemic read failure would evict the real destructive-action trail.
        #
        # The difference is structural, not a judgement call. `Doctor#call` IS
        # the diagnostic entry point — its checks run whether or not `repair` is
        # set — whereas this op's `#call` is reached from the doctor only inside
        # `return unless repair`, i.e. it never runs on a diagnostic pass. Its
        # events are therefore already bounded by the number of domains an
        # operator explicitly asked to MUTATE, which is the same bound the
        # success event has always had on that path. (`domains bulk-repair`, the
        # other historical fleet driver, is a deprecation shim that exits before
        # loading anything.)
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @domain&.extid },
          detail: -> { { dry_run: @dry_run } }

        # @!attribute status [r] Symbol —
        #   :no_issues (consistent), :needs_org (orphaned, no target given),
        #   :org_not_found (org_id set but org missing), :planned (dry-run, fixable
        #   issues found), :repaired (issues applied)
        Result = Data.define(
          :status,
          :domain_id,
          :extid,
          :display_domain,
          :issues,
          :repairs_applied,
          :dry_run,
        )

        # @param domain [Onetime::CustomDomain] target domain (caller ensures non-nil).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or the CLI sentinel). Never an internal objid.
        # @param org [Onetime::Organization, nil] target org for the ORPHANED case
        #   (the CLI's --org-id, resolved by the adapter). Ignored when org_id is set.
        # @param dry_run [Boolean] preview only when true (default). Applies when false.
        def initialize(domain:, actor:, org: nil, dry_run: true)
          @domain  = domain
          @actor   = actor
          @org     = org
          @dry_run = dry_run
        end

        # @return [Result]
        def call
          issues, repairs, blocked = analyze

          return blocked if blocked
          return result_for(:no_issues, issues, []) if issues.empty?

          # A preview repairs nothing, so nothing reaches the OPERATOR trail —
          # but it enumerates a customer domain's defects, and `dry_run`
          # defaults to TRUE here, so this is the path an operator takes first.
          # Recorded as an OBSERVATION (#4337).
          if @dry_run
            record_preview_event(issues)
            return result_for(:planned, issues, [])
          end

          # Apply every repair, collecting the human-readable result of each.
          repairs_applied = repairs.map(&:call)

          # Exactly one audit event per successful mutation. Non-secret detail only.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @domain.extid,
            result: :success,
            detail: {
              issues: issues,
              org_id: @domain.org_id.to_s,
            },
          )

          result_for(:repaired, issues, repairs_applied)
        end

        private

        # One OBSERVATION per preview (#4337), on the budgeted access trail.
        # Same verb, target and `issues` detail as the applied event, so a
        # preview and the repair that followed read as one sequence;
        # `result: 'preview'` is what tells them apart.
        def record_preview_event(issues)
          Onetime::ColonelAuditEvent.record_access(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @domain.extid,
            result: 'preview',
            detail: {
              dry_run: true,
              issues: issues,
              org_id: @domain.org_id.to_s,
            },
          )
        end

        # Compute [issues<Array<String>>, repairs<Array<#call>>, blocked<Result|nil>].
        # A repair is a lambda returning its human-readable result string when applied.
        def analyze
          issues  = []
          repairs = []

          if @domain.org_id.to_s.empty?
            # Case 1: orphaned.
            unless @org
              return [issues, repairs, result_for(:needs_org, [], [])]
            end

            issues << 'Domain is orphaned (no org_id)'
            org = @org
            repairs << -> do
              @domain.org_id  = org.org_id
              @domain.updated = OT.now.to_i
              @domain.save
              # The `owners` class hashkey is a second ownership index that
              # nothing maintains automatically; adopting an orphan has to
              # write it or the org-deletion drift guard
              # (Organization#unlisted_owned_domains) never learns who owns
              # this domain. Same reason Domains::Transfer writes it.
              Onetime::CustomDomain.record_owner(@domain, org.org_id)
              org.add_domain(@domain)
              "Assigned to organization #{org.org_id}"
            end
          else
            # Case 2: org_id set — verify the org exists and the collection contains it.
            org = Onetime::Organization.load(@domain.org_id)
            unless org
              return [issues, repairs, result_for(:org_not_found, [], [])]
            end

            in_collection = org.list_domains.map(&:domainid).include?(@domain.domainid)
            unless in_collection
              issues << "org_id is #{@domain.org_id} but not in organization's domains collection"
              repairs << -> do
                org.add_domain(@domain)
                "Added to organization #{@domain.org_id} collection"
              end
            end
          end

          [issues, repairs, nil]
        end

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op.
        def record_refusal(status)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @domain.extid,
            result: :failure,
            detail: {
              reason: status.to_s,
              org_id: @domain.org_id.to_s,
              dry_run: @dry_run,
            },
          )
        rescue StandardError => ex
          OT.le "[Domains::Repair] refusal audit failed: #{ex.class}: #{ex.message}"
        end

        # Single exit point for every status, so the refusal audit cannot be
        # forgotten at either of the two blocked returns inside #analyze.
        def result_for(status, issues, repairs_applied)
          record_refusal(status) if REFUSAL_STATUSES.include?(status)

          Result.new(
            status: status,
            domain_id: @domain.domainid,
            extid: @domain.extid,
            display_domain: @domain.display_domain,
            issues: issues,
            repairs_applied: repairs_applied,
            dry_run: @dry_run,
          )
        end
      end
    end
  end
end
