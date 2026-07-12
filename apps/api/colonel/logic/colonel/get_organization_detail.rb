# apps/api/colonel/logic/colonel/get_organization_detail.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../apps/web/billing/lib/billing_service'

module ColonelAPI
  module Logic
    module Colonel
      # Get Organization Detail (Colonel)
      #
      # @api Full read-out for a single organization, keyed by PUBLIC id
      #   (extid). Powers the `/colonel/organizations/:id` detail page: billing
      #   state, the *current* entitlement state (plan / grants / revokes /
      #   materialized + drift), the member roster and the domain roster.
      #   Requires colonel role.
      #
      # Emails are returned in FULL (this is a colonel-only, scope=internal
      # surface). The admin UI obscures them by default and reveals on
      # interaction — masking here would make that affordance impossible and
      # deny the operator the address they legitimately need for support and
      # billing work. See RevealEmail.vue.
      #
      # The entitlement block is the gap this endpoint closes: the org LIST
      # carries no entitlement data, and the override panel previously surfaced
      # state only *after* a mutation, so the operator edited blind. Here the
      # four source sets are returned alongside a computed `expected`
      # (plan ∪ grants − revokes — the formula #apply_entitlements applies) and
      # the `drift` between expected and materialized, which flags orphaned
      # entries (e.g. a stray entitlement left in `materialized` after its
      # source was cleared) an operator otherwise cannot see.
      #
      class GetOrganizationDetail < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelOrganizationDetail' }.freeze

        attr_reader :org

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
          success_data
        end

        private

        # Resolve by PUBLIC id (extid) first — every admin surface routes by
        # extid — then fall back to objid. Mirrors InvestigateOrganization /
        # ManageEntitlementOverride#load_organization.
        def load_organization
          org = Onetime::Organization.find_by_extid(@org_id)
          return org if org

          Onetime::Organization.load(@org_id)
        end

        def owner
          @owner ||= org.owner
        end

        # Current entitlement state + drift. `expected` mirrors the reconciliation
        # #apply_entitlements performs (plan ∪ grants − revokes); `drift.extra` is
        # what materialized holds beyond that (orphans), `drift.missing` is what
        # should be materialized but isn't.
        def build_entitlements
          plan_set     = org.entitlements_plan.to_a
          grants       = org.entitlements_grants.to_a
          revokes      = org.entitlements_revokes.to_a
          materialized = org.materialized_entitlements.to_a

          expected = ((plan_set | grants) - revokes)
          extra    = (materialized - expected).sort
          missing  = (expected - materialized).sort

          applied = org.materialized_entitlements_at_parsed

          {
            plan: plan_set.sort,
            grants: grants.sort,
            revokes: revokes.sort,
            materialized: materialized.sort,
            expected: expected.sort,
            materialized_flag: org.entitlements_materialized?,
            materialized_at: applied ? applied[:timestamp] : nil,
            plan_stale: compute_plan_stale,
            drift: {
              extra: extra,
              missing: missing,
              in_sync: extra.empty? && missing.empty?,
            },
          }
        end

        # Plan-definition drift: has the plan's entitlement/limit content changed
        # since it was last materialized? Distinct from override drift above.
        # Returns nil when the plan can't be loaded (can't compare) rather than
        # asserting a state we can't verify.
        def compute_plan_stale
          planid = org.planid.to_s
          return nil if planid.empty?

          plan = Billing::Plan.load(planid) || Billing::Plan.load_from_config(planid)
          return nil unless plan

          org.entitlements_stale?(plan)
        rescue StandardError
          nil
        end

        # Member roster with role + status from the active memberships. Falls
        # back to a bare customer row if the membership record is missing (the
        # member zset can outlive a deleted membership).
        def build_members
          memberships = Onetime::OrganizationMembership.active_for_org(org)
          by_customer = memberships.to_h { |m| [m.customer_objid, m] }

          org.list_members.map do |cust|
            membership = by_customer[cust.objid]
            {
              extid: cust.extid,
              email: cust.email,
              role: membership&.role,
              status: membership&.status,
              is_owner: cust.objid == org.owner_id,
              joined_at: membership&.joined_at&.to_i,
              created: cust.created&.to_i,
            }
          end
        end

        def build_domains
          org.list_domains.map do |domain|
            {
              extid: domain.extid,
              domain_id: domain.domainid,
              display_domain: domain.display_domain,
              base_domain: domain.base_domain,
              status: domain.status,
              verified: domain.verified.to_s == 'true',
              resolving: domain.resolving.to_s == 'true',
              verification_state: domain.verification_state.to_s,
              ready: domain.ready?,
              created: domain.created&.to_i,
            }
          end
        end

        def success_data
          {
            record: {
              org_id: org.objid,
              extid: org.extid,
              display_name: org.display_name,
              description: org.description,
              is_default: org.is_default.to_s == 'true',
              archived: org.archived?,
              archived_at: org.archived_at&.to_i,
              archived_comment: org.archived_comment,
              # FULL addresses — obscured client-side, revealed on interaction.
              contact_email: org.contact_email,
              owner_id: org.owner_id,
              owner_email: owner&.email,
              billing_email: org.billing_email,
              member_count: org.member_count,
              domain_count: org.domain_count,
              created: org.created&.to_i,
              updated: org.updated&.to_i,
              # Billing
              planid: org.planid,
              stripe_customer_id: org.stripe_customer_id,
              stripe_subscription_id: org.stripe_subscription_id,
              subscription_status: org.subscription_status,
              subscription_period_end: org.subscription_period_end,
              billing_email_present: !org.billing_email.to_s.empty?,
              sync_status: Billing::BillingService.compute_sync_status(org),
              sync_status_reason: Billing::BillingService.compute_sync_status_reason(org),
            },
            details: {
              entitlements: build_entitlements,
              members: build_members,
              domains: build_domains,
            },
          }
        end
      end
    end
  end
end
