# apps/api/colonel/logic/colonel/reconcile_organization.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/org/reconcile'

module ColonelAPI
  module Logic
    module Colonel
      # Reconcile Organization (Colonel) — THIN ADAPTER.
      #
      # The remediation counterpart to InvestigateOrganization. Investigate is
      # read-only — it surfaces a local↔Stripe mismatch but offers no fix. This
      # writes the authoritative state back.
      #
      # All behaviour (mode selection, the Stripe re-pull, entitlement
      # re-materialization, the before/after snapshot and the SINGLE admin audit
      # event) lives in {Onetime::Operations::Org::Reconcile} — the one
      # implementation shared with `bin/ots org reconcile`. This class owns only
      # HTTP concerns: params, authorization, and the response shape.
      #
      # DO NOT re-add an audit event here. The op emits exactly one; a second
      # would double-record the trail.
      #
      # MUTATING + guarded (typed confirmation client-side) + audited in the op,
      # mirroring ManageEntitlementOverride.
      #
      # No `?dry_run=1` preview (decision D12): the op supports it, but the admin
      # UI has no preview flow today, so this adapter pins `dry_run: false`.
      #
      class ReconcileOrganization < ColonelAPI::Logic::Base
        attr_reader :org, :result

        def process_params
          @org_id = sanitize_identifier(params['org_id'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?

          @org = load_organization
          raise_not_found('Organization not found') unless @org&.exists?
        end

        def process
          @result = Onetime::Operations::Org::Reconcile.new(
            org: @org,
            actor: cust.extid,
            dry_run: false,
          ).call

          # Preserve the pre-extraction 4xx contract: a Stripe failure is a form
          # error, not a 200 with an error status.
          raise_form_error("Stripe error: #{@result.reason}") if @result.status == :stripe_error

          success_data
        end

        private

        # extid-first with an objid fallback — the org resolution precedence
        # shared with GetOrganizationDetail and mirrored by the CLI's
        # Onetime::CLI::Org::Shared#resolve_org.
        def load_organization
          org = Onetime::Organization.find_by_extid(@org_id)
          return org if org

          Onetime::Organization.load(@org_id)
        end

        # WIRE CONTRACT — do not "tidy" these keys.
        #
        # `org_id` is the INTERNAL objid and stays that way: it is what
        # src/schemas/api/internal/responses/colonel-organizations.ts
        # (colonelReconcileOrganizationRecordSchema) and
        # AdminOrganizationDetail.vue already consume. The op's own Result and
        # audit detail are extid-only; this response keeps both ids.
        #
        # `status` is `result.status.to_s`, which is why the op's status
        # vocabulary reuses the engine's strings ('applied', 'materialized',
        # 'skipped_no_plan', …) verbatim.
        # `memberships` is the cascade outcome (#3907 item 3) — counts from
        # `rematerialize_all_memberships!`, or null when the run did not
        # cascade (skips) or the cascade raised (logs carry that case).
        # `failed_ids` are membership objids, consistent with `org_id` above.
        def success_data
          {
            record: {
              org_id: org.objid,
              extid: org.extid,
              mode: result.mode,
              status: result.status.to_s,
              reason: result.reason,
              before: result.before,
              after: result.after,
              memberships: result.memberships,
            },
          }
        end
      end
    end
  end
end
