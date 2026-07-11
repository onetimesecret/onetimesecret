# apps/api/colonel/logic/colonel/manage_entitlement_override.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Manage Entitlement Overrides
      #
      # Allows colonels to grant or revoke entitlements on an organization,
      # independent of the organization's plan. Useful for:
      # - Grandfathered access to deprecated features
      # - Beta feature rollout
      # - Complimentary upgrades
      # - Temporary access grants
      #
      # Overrides persist across plan changes and are applied during reconciliation:
      #   effective = plan_entitlements + grants - revokes
      #
      # ## Endpoints
      #
      # POST /api/colonel/organizations/:org_id/entitlements/grant
      # POST /api/colonel/organizations/:org_id/entitlements/revoke
      # DELETE /api/colonel/organizations/:org_id/entitlements/overrides
      #
      # ## Request Body
      #
      # { "entitlement": "custom_domains" }
      #
      # ## Response
      #
      # {
      #   "org_id": "abc123",
      #   "entitlement": "custom_domains",
      #   "action": "granted" | "revoked" | "cleared",
      #   "effective_entitlements": ["create_secrets", "custom_domains", ...],
      #   "grants": ["custom_domains"],
      #   "revokes": []
      # }
      #
      class ManageEntitlementOverride < ColonelAPI::Logic::Base
        ACTION_PAST_TENSE = {
          'grant' => 'granted',
          'revoke' => 'revoked',
          'clear' => 'cleared',
        }.freeze

        attr_reader :org, :entitlement, :action

        def process_params
          @org_id      = sanitize_identifier(params['org_id'])
          @entitlement = params['entitlement']&.to_s&.strip

          # Action comes from URL path:
          # - POST /entitlements/:action  -> params['action'] = 'grant' or 'revoke'
          # - DELETE /entitlements/overrides -> params['action'] = nil (literal path, not param)
          url_action = params['action']&.to_s&.downcase
          @action    = url_action.to_s.empty? ? 'clear' : url_action

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?

          unless %w[grant revoke clear].include?(@action)
            raise_form_error('Action must be grant or revoke', field: :action)
          end

          if @action != 'clear' && @entitlement.to_s.empty?
            raise_form_error('Entitlement is required for grant/revoke', field: :entitlement)
          end
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @org = load_organization
          raise_not_found('Organization not found') unless @org&.exists?

          # Validate entitlement name is known (optional, but helps catch typos)
          return if @action == 'clear'

          known = Billing::Config.load_entitlements.keys
          return if known.include?(@entitlement)

          # Warn but don't block - allows granting future entitlements
          OT.info "[colonel] Granting unknown entitlement '#{@entitlement}' to org #{@org_id}"
        end

        def process
          case @action
          when 'grant'
            @org.grant_entitlement(@entitlement)
          when 'revoke'
            @org.revoke_entitlement(@entitlement)
          when 'clear'
            @org.clear_entitlement_overrides
          end

          record_audit_event

          success_data
        end

        def success_data
          {
            record: {
              org_id: @org.objid,
              extid: @org.extid,
              entitlement: @entitlement,
              action: action_past_tense,
              effective_entitlements: @org.materialized_entitlements.to_a,
              grants: @org.entitlements_grants.to_a,
              revokes: @org.entitlements_revokes.to_a,
            },
          }
        end

        private

        # Resolve the target org by PUBLIC id (extid) first — the admin
        # organizations screen routes exclusively by extid — then fall back to
        # objid so existing objid-based callers (CLI, older integrations) keep
        # working. Mirrors InvestigateOrganization#load_organization.
        def load_organization
          org = Onetime::Organization.find_by_extid(@org_id)
          return org if org

          Onetime::Organization.load(@org_id)
        end

        # One audit event per successful entitlement-override mutation
        # (CONTRACT 4 / epic D4). Emitted from the logic layer: this
        # billing-domain verb has no extracted Operation yet (a dedicated
        # billing op is deferred to a follow-up per the epic's "improvements
        # ship as separate PRs"), so the non-negotiable audit backstop lives
        # here. actor/target are PUBLIC ids (never objids); AdminAuditEvent.record
        # is best-effort and swallows its own failures, so it never breaks the op.
        def record_audit_event
          Onetime::AdminAuditEvent.record(
            actor: cust.extid,
            verb: "organization.entitlement.#{@action}",
            target: @org.extid,
            result: :success,
            detail: @action == 'clear' ? {} : { entitlement: @entitlement },
          )
        end

        def action_past_tense
          ACTION_PAST_TENSE[@action]
        end
      end
    end
  end
end
