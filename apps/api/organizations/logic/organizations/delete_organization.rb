# apps/api/organizations/logic/organizations/delete_organization.rb
#
# frozen_string_literal: true

require 'onetime/operations/org/delete'

module OrganizationAPI::Logic
  module Organizations
    # Delete Organization
    #
    # @api Permanently deletes an organization, removing all member
    #   associations first. Requires the `manage_org` entitlement in the target
    #   organization. Returns a confirmation of deletion.
    #
    # THIN ADAPTER over {Onetime::Operations::Org::Delete} — the single
    # implementation of the delete verb (#3731 P3, "one destroy path"), shared
    # with `bin/ots org delete` and `DELETE /api/colonel/organizations/:org_id`.
    # This class owns only customer-facing concerns: the authz gate, the
    # guardrail → form-error mapping, and the response shape. IT CONTAINS NO
    # TEARDOWN LOGIC — that lived here before, which is exactly why the shell
    # could not reach it and a hand-run `destroy!` left `Organization.instances`
    # dangling, mailed nobody, and left `default_org_id` pointing at a dead org.
    #
    # ## What moving the teardown into the op changed for THIS endpoint
    #
    # The op's guardrails now apply to customers too, and two of them are new
    # behaviour here:
    #
    # - `:is_default` — a default (personal) workspace can no longer be deleted
    #   through this endpoint. That rule already existed in
    #   `Organization#can_delete?` (which has NEVER had a caller) and in a Vue
    #   `v-if`; a direct `DELETE /api/organizations/:extid` bypassed both and
    #   deleted the owner's default workspace. The server now enforces what the
    #   UI has been promising alone. The op's `force_default` escape hatch is
    #   OPERATOR-ONLY and deliberately not passed from here.
    # - `:active_subscription` — an org that is actively billing must have its
    #   subscription cancelled first. Nothing in this path talks to Stripe, so
    #   deleting the org would strand a live subscription against a record that
    #   no longer exists.
    #
    # `:has_domains` was already a refusal, but it arrived as a raw
    # `Onetime::Problem` out of `destroy!`; it is now a form error naming the
    # domains. `:last_org` is new and refuses to strand an account with no
    # workspace at all.
    #
    # ## Audit
    #
    # The op emits the single `organization.delete` ColonelAuditEvent on the
    # applied path. DO NOT audit here — a second event would double-record.
    class DeleteOrganization < OrganizationAPI::Logic::Base
      SCHEMAS = { response: 'organizationDelete' }.freeze

      attr_reader :organization, :result

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        # Require authenticated user
        verify_authenticated!

        # Validate extid parameter
        if @extid.to_s.empty?
          raise_form_error(
            error_key: 'api.organizations.errors.extid_required',
            field: :extid,
            error_type: :missing,
          )
        end

        # Load organization
        @organization = load_organization(@extid)

        # Verify user has manage_org entitlement in this organization
        require_entitlement_in!(@organization, 'manage_org')

        # NO domain pre-check here. The op owns every guardrail, and a duplicate
        # `domain_count` refusal at this layer would short-circuit its drift
        # self-heal — the customer would be told to remove domains they cannot
        # see, instead of having the invisible ones repaired back into view.
      end

      def process
        OT.ld "[DeleteOrganization] Deleting organization #{@extid} for user #{cust.extid}"

        @result = Onetime::Operations::Org::Delete.new(
          org: @organization,
          # The acting customer's PUBLIC id (never an objid) — this is a
          # customer-initiated delete, so the trail names them, not a sentinel.
          actor: cust.extid,
          # Customer-facing: apply immediately (there is no preview flow in the
          # UI), and NEVER pass a force flag — every guardrail is absolute here.
          dry_run: false,
          # Former members have always seen the acting customer's address in the
          # organization_deleted mail; keep that wording unchanged.
          deleted_by: cust.email,
        ).call

        refuse_unless_applied

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          deleted: true,
          extid: @extid,
        }
      end

      def form_fields
        {
          extid: @extid,
        }
      end

      private

      # Map the op's guardrail vocabulary onto customer-facing form errors. The
      # vocabulary is closed, so an unrecognised status fails loudly rather than
      # reporting a delete that did not happen.
      def refuse_unless_applied
        case result.status
        when :success
          nil # Fall through to success_data.
        when :has_domains
          raise_form_error(
            error_key: 'api.organizations.errors.delete_has_domains',
            # Names are best-effort: a stale entry in the domains collection
            # loads to nothing, so fall back to the count the guard actually
            # refused on rather than interpolating an empty list.
            args: { domains: result.domains.empty? ? result.domain_count.to_s : result.domains.join(', ') },
            field: :extid,
            error_type: :invalid,
          )
        when :drifted_domains
          # The self-heal already ran and could not restore these, so they stay
          # INVISIBLE in the customer's domain list — "remove your domains" would
          # be pointing at nothing they can see. Name them and route to support.
          raise_form_error(
            error_key: 'api.organizations.errors.delete_drifted_domains',
            args: { domains: result.drifted_domains.join(', ') },
            field: :extid,
            error_type: :invalid,
          )
        when :is_default
          raise_form_error(
            error_key: 'api.organizations.errors.delete_is_default',
            field: :extid,
            error_type: :invalid,
          )
        when :active_subscription
          raise_form_error(
            error_key: 'api.organizations.errors.delete_active_subscription',
            field: :extid,
            error_type: :invalid,
          )
        when :last_org
          raise_form_error(
            error_key: 'api.organizations.errors.delete_last_org',
            field: :extid,
            error_type: :invalid,
          )
        else
          # :planned is impossible (dry_run is pinned false above) — seeing it
          # means the pin broke, not that a preview happened.
          raise Onetime::Problem, "Unexpected delete status: #{result.status}"
        end
      end
    end
  end
end
