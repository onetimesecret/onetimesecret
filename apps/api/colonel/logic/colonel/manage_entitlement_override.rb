# apps/api/colonel/logic/colonel/manage_entitlement_override.rb
#
# frozen_string_literal: true

require_relative '../base'

# The Logic layer runs outside the lib/ autoloaders — require the shared op
# explicitly. This class is now a THIN ADAPTER over it; the mutation, the
# no-change semantics and the admin audit event all live in the op.
require 'onetime/operations/org/entitlement_override'

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
      # ## Adapter, not implementation (#3731)
      #
      # The single implementation is
      # {Onetime::Operations::Org::EntitlementOverride} — shared with
      # `bin/ots org entitlement …`. This class owns only HTTP concerns:
      # deriving the action from the URL path, colonel authorization, resolving
      # the org, the catalog typo warning, and shaping the response. It MUST NOT
      # record an audit event; the op does that exactly once.
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
        # Kept here (not read from the op) because it is part of THIS surface's
        # response contract — src/apps/admin/views/AdminOrganizationDetail.vue
        # renders the past-tense string.
        ACTION_PAST_TENSE = Onetime::Operations::Org::EntitlementOverride::ACTION_PAST_TENSE

        # Derived from the op's ACTIONS so the operator-facing message cannot
        # drift from what is actually accepted. 'clear' IS valid here: DELETE
        # /entitlements/overrides carries no action param and maps to it, so a
        # message naming only grant/revoke misleads on that surface.
        VALID_ACTIONS_MESSAGE = "Action must be one of: #{
          Onetime::Operations::Org::EntitlementOverride::ACTIONS.join(', ')
        }".freeze

        attr_reader :org, :entitlement, :action, :result

        def process_params
          @org_id      = sanitize_identifier(params['org_id'])
          @entitlement = params['entitlement']&.to_s&.strip

          # Action comes from URL path:
          # - POST /entitlements/:action  -> params['action'] = 'grant' or 'revoke'
          # - DELETE /entitlements/overrides -> params['action'] = nil (literal path, not param)
          url_action = params['action']&.to_s&.downcase
          @action    = url_action.to_s.empty? ? 'clear' : url_action

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?

          unless Onetime::Operations::Org::EntitlementOverride::ACTIONS.include?(@action)
            raise_form_error(VALID_ACTIONS_MESSAGE, field: :action)
          end

          if @action != 'clear' && @entitlement.to_s.empty?
            raise_form_error('Entitlement is required for grant/revoke', field: :entitlement)
          end
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @org = load_organization
          raise_not_found('Organization not found') unless @org&.exists?

          # TIER 2 (#4326), ALL arms: grant is privilege-granting and clear is
          # irreversible, so a per-arm split would buy nothing but a place to
          # make a mistake. The URL carries the org id; the confirmation is its
          # NAME.
          guard_destructive_action!(
            tier: :sensitive,
            confirm_with: org_confirm_token(@org),
            confirm_subject: "the organization's name",
            field: :org_id,
          )

          warn_unknown_entitlement
        end

        def process
          @result = Onetime::Operations::Org::EntitlementOverride.new(
            org: @org,
            action: @action,
            actor: cust.extid,
            entitlement: @entitlement,
            # The console has no preview flow (D12) — this surface always applies.
            dry_run: false,
          ).call

          handle_result_status(@result)

          success_data
        end

        def success_data
          {
            record: {
              org_id: @org.objid,
              extid: @org.extid,
              entitlement: @entitlement,
              action: action_past_tense,
              effective_entitlements: @result.effective,
              grants: @result.grants,
              revokes: @result.revokes,
            },
          }
        end

        private

        # Warn but don't block — allows granting future entitlements. Validation
        # of the entitlement NAME is advisory (it helps catch typos); it is not a
        # guard, so it deliberately runs after the confirmation gate.
        def warn_unknown_entitlement
          return if @action == 'clear'
          return if Onetime::Operations::Org::EntitlementOverride.known_entitlement?(@entitlement)

          OT.info "[colonel] Granting unknown entitlement '#{@entitlement}' to org #{@org_id}"
        end

        # Statuses the op returns for input it refused. process_params already
        # rejects both ahead of the call, so these are a defensive backstop that
        # keeps the 400 contract intact if the op's validation ever widens.
        #
        # :no_change is a successful, idempotent 200 — the entitlement is already
        # in the requested state, so the response below describes reality.
        def handle_result_status(result)
          case result.status
          when :invalid_action
            raise_form_error(VALID_ACTIONS_MESSAGE, field: :action)
          when :missing_entitlement
            raise_form_error('Entitlement is required for grant/revoke', field: :entitlement)
          end
        end

        # Resolve the target org by PUBLIC id (extid) first — the admin
        # organizations screen routes exclusively by extid — then fall back to
        # objid so existing objid-based callers (CLI, older integrations) keep
        # working. Mirrors InvestigateOrganization#load_organization.
        def load_organization
          org = Onetime::Organization.find_by_extid(@org_id)
          return org if org

          Onetime::Organization.load(@org_id)
        end

        def action_past_tense
          ACTION_PAST_TENSE[@action]
        end
      end
    end
  end
end
