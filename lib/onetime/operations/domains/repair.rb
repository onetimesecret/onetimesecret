# lib/onetime/operations/domains/repair.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — see decision D3 in
# lib/onetime/operations/README.md. Lives alongside the incumbent domain ops in
# lib/onetime/operations, under the Domains:: namespace. Loaded at the call site
# (colonel logic + CLI), so require the audit model explicitly, mirroring
# AdminVerifyDomain / BanIP.
require 'onetime/models/admin_audit_event'

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
      # applies the repairs and records EXACTLY ONE {Onetime::AdminAuditEvent} per
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
        # Audit verb recorded for every applied repair.
        AUDIT_VERB = 'domain.repair'

        # @!attribute status [r] Symbol —
        #   :no_issues (consistent), :needs_org (orphaned, no target given),
        #   :org_not_found (org_id set but org missing), :planned (dry-run, fixable
        #   issues found), :repaired (issues applied)
        Result = Data.define(
          :status, :domain_id, :extid, :display_domain,
          :issues, :repairs_applied, :dry_run
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
          return result_for(:planned, issues, []) if @dry_run

          # Apply every repair, collecting the human-readable result of each.
          repairs_applied = repairs.map(&:call)

          # Exactly one audit event per successful mutation. Non-secret detail only.
          Onetime::AdminAuditEvent.record(
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
            repairs << lambda do
              @domain.org_id  = org.org_id
              @domain.updated = OT.now.to_i
              @domain.save
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
              repairs << lambda do
                org.add_domain(@domain)
                "Added to organization #{@domain.org_id} collection"
              end
            end
          end

          [issues, repairs, nil]
        end

        def result_for(status, issues, repairs_applied)
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
