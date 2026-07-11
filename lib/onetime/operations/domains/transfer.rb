# lib/onetime/operations/domains/transfer.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — see decision D3 in
# lib/onetime/operations/README.md. Lives alongside the incumbent domain ops in
# lib/onetime/operations, under the Domains:: namespace. Loaded at the call site
# (colonel logic + CLI), so require the audit model explicitly.
require 'onetime/models/admin_audit_event'

module Onetime
  module Operations
    module Domains
      # Transfer a custom domain between organizations — the SINGLE implementation
      # of the transfer verb (epic #43 / D3 / CONTRACT 4). This is the
      # highest-blast-radius toolbox verb: it reassigns domain OWNERSHIP across
      # organizations. The `bin/ots domains transfer` CLI and the colonel endpoint
      # (`POST /api/colonel/domains/:extid/transfer`) are thin adapters over it.
      #
      # ## Source of truth for "from" (parity with the CLI)
      #
      # The domain is ALWAYS removed from its CURRENT owner's collection (resolved
      # from `domain.org_id`), whether or not an explicit `from_org` was supplied —
      # this mirrors the CLI, which derives `from_org_id = --from-org || domain.org_id`
      # and removes from that org. `from_org` is an optional OWNERSHIP ASSERTION:
      # when supplied and its id does not equal the domain's current owner, the op
      # returns `:mismatch` and mutates nothing (the CLI's "org_id does not match
      # --from-org" guard). A domain with a blank `org_id` transfers from "orphaned"
      # (nothing to remove).
      #
      # ## Dry-run + exactly-once audit (CONTRACT 4)
      #
      # `dry_run: true` (the safe default) returns the transfer plan (from/to org
      # names + ids) and mutates/audits NOTHING. `dry_run: false` performs the
      # transfer (remove from old collection → update org_id → add to new
      # collection, rolling back org_id if the add fails) and records EXACTLY ONE
      # {Onetime::AdminAuditEvent}. A blocked run (`:mismatch`) records no event.
      #
      # ## Behavioural parity note
      #
      # The collection add/remove use the domain's `domainid` STRING argument
      # (`org.add_domain(domain.domainid)` / `org.remove_domain(domain.domainid)`),
      # exactly matching the pre-refactor CLI (`bin/ots domains transfer`). This is
      # the single shared impl for BOTH the CLI and the colonel endpoint, so both
      # adapters pass the identical string argument.
      class Transfer
        # Audit verb recorded for every applied transfer.
        AUDIT_VERB = 'domain.transfer'

        # @!attribute status [r] Symbol —
        #   :planned (dry-run), :transferred (applied),
        #   :mismatch (explicit from_org != current owner — blocked)
        Result = Data.define(
          :status, :domain_id, :extid, :display_domain,
          :from_org_id, :from_org_name, :to_org_id, :to_org_name, :dry_run
        )

        # @param domain [Onetime::CustomDomain] target domain (caller ensures non-nil).
        # @param to_org [Onetime::Organization] destination org (caller resolves; required).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        # @param from_org [Onetime::Organization, nil] optional source-org ASSERTION
        #   for the ownership check; nil = trust the domain's current org_id.
        # @param dry_run [Boolean] preview only when true (default). Applies when false.
        def initialize(domain:, to_org:, actor:, from_org: nil, dry_run: true)
          @domain   = domain
          @to_org   = to_org
          @actor    = actor
          @from_org = from_org
          @dry_run  = dry_run
        end

        # @return [Result]
        def call
          # Snapshot the CURRENT owner before any mutation — this is the real "from".
          original_from_id = @domain.org_id
          current_org      = original_from_id.to_s.empty? ? nil : Onetime::Organization.load(original_from_id)
          original_from_nm = current_org&.display_name

          # Ownership guard: an explicit from_org must match the current owner.
          if @from_org && @from_org.org_id.to_s != original_from_id.to_s
            return build(:mismatch, original_from_id, original_from_nm)
          end

          return build(:planned, original_from_id, original_from_nm) if @dry_run

          # Remove from the old organization's collection, if there is one.
          current_org&.remove_domain(@domain.domainid)

          # Update the domain's owner.
          @domain.org_id  = @to_org.org_id
          @domain.updated = OT.now.to_i
          @domain.save

          # Add to the new organization's collection, rolling back org_id on failure.
          begin
            @to_org.add_domain(@domain.domainid)
          rescue StandardError => ex
            @domain.org_id = original_from_id
            @domain.save
            raise "Failed to add domain to organization collection: #{ex.message}"
          end

          # Exactly one audit event per successful transfer. Non-secret detail only.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @domain.extid,
            result: :success,
            detail: {
              from_org_id: original_from_id.to_s,
              to_org_id: @to_org.org_id.to_s,
            },
          )

          build(:transferred, original_from_id, original_from_nm)
        end

        private

        def build(status, from_id, from_name)
          Result.new(
            status: status,
            domain_id: @domain.domainid,
            extid: @domain.extid,
            display_domain: @domain.display_domain,
            from_org_id: from_id,
            from_org_name: from_name,
            to_org_id: @to_org.org_id,
            to_org_name: @to_org.display_name,
            dry_run: @dry_run,
          )
        end
      end
    end
  end
end
