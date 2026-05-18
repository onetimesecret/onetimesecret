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

          # Action comes from URL path: /entitlements/:action or DELETE /entitlements/overrides
          @action = if req.request_method == 'DELETE'
                      'clear'
                    else
                      params['action']&.to_s&.downcase
                    end

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?
          raise_form_error('Action is required', field: :action) if @action.to_s.empty?

          unless %w[grant revoke clear].include?(@action)
            raise_form_error('Action must be grant or revoke', field: :action)
          end

          if @action != 'clear' && @entitlement.to_s.empty?
            raise_form_error('Entitlement is required for grant/revoke', field: :entitlement)
          end
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @org = Onetime::Organization.load(@org_id)
          raise_not_found('Organization not found') unless @org&.exists?

          # Validate entitlement name is known (optional, but helps catch typos)
          return if @action == 'clear'

          known = Billing::Config.all_entitlements
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

          success_data
        end

        def success_data
          {
            org_id: @org.objid,
            extid: @org.extid,
            entitlement: @entitlement,
            action: action_past_tense,
            effective_entitlements: @org.materialized_entitlements.to_a,
            grants: @org.entitlements_grants.to_a,
            revokes: @org.entitlements_revokes.to_a,
          }
        end

        private

        def action_past_tense
          ACTION_PAST_TENSE[@action]
        end
      end
    end
  end
end
