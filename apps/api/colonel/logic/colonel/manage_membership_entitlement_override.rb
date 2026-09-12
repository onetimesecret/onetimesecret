# apps/api/colonel/logic/colonel/manage_membership_entitlement_override.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'membership_resolvers'

# The Logic layer runs outside the lib/ autoloaders — require the shared op
# explicitly. This class is a THIN ADAPTER over it; the mutation, the
# no-change semantics and the admin audit event all live in the op.
require 'onetime/operations/memberships/entitlement_override'

module ColonelAPI
  module Logic
    module Colonel
      # Manage Membership Entitlement Overrides (#3907, closing D19 of #3731)
      #
      # Allows colonels to grant or revoke entitlements on a single org
      # MEMBERSHIP, independent of the org's plan and the member's role
      # template. The membership-scoped sibling of ManageEntitlementOverride —
      # same URL shape one level down, same response shape plus `member_id`.
      #
      # Overrides persist across role changes and re-materialization:
      #   effective = (org ∩ role template) + grants - revokes
      #
      # ## Adapter, not implementation
      #
      # The single implementation is
      # {Onetime::Operations::Memberships::EntitlementOverride} — shared with
      # `bin/ots memberships entitlement …`. This class owns only HTTP
      # concerns: deriving the action from the URL path, colonel
      # authorization, resolving the org + member, the catalog typo warning,
      # and shaping the response. It MUST NOT record an audit event; the op
      # does that exactly once.
      #
      # ## Endpoints
      #
      # POST /api/colonel/organizations/:org_id/members/:member_id/entitlements/grant
      # POST /api/colonel/organizations/:org_id/members/:member_id/entitlements/revoke
      # DELETE /api/colonel/organizations/:org_id/members/:member_id/entitlements/overrides
      #
      # ## Request Body
      #
      # { "entitlement": "custom_domains" }
      #
      # ## Response
      #
      # {
      #   "org_id": "on_abc123",
      #   "member_id": "ur_def456",
      #   "entitlement": "custom_domains",
      #   "action": "granted" | "revoked" | "cleared",
      #   "effective_entitlements": ["create_secrets", "custom_domains", ...],
      #   "grants": ["custom_domains"],
      #   "revokes": []
      # }
      #
      class ManageMembershipEntitlementOverride < ColonelAPI::Logic::Base
        include MembershipResolvers

        # Cross-referenced by OpenAPI generation (scripts/openapi) against the
        # internal response registry key in registry.ts.
        SCHEMAS = { response: 'colonelMembershipEntitlementOverride' }.freeze

        # Kept here (not read from the op) because it is part of THIS surface's
        # response contract — the admin bundle renders the past-tense string.
        ACTION_PAST_TENSE = Onetime::Operations::Memberships::EntitlementOverride::ACTION_PAST_TENSE

        # Derived from the op's ACTIONS so the operator-facing message cannot
        # drift from what is actually accepted. 'clear' IS valid here: DELETE
        # /entitlements/overrides carries no action param and maps to it, so a
        # message naming only grant/revoke misleads on that surface.
        VALID_ACTIONS_MESSAGE = "Action must be one of: #{
          Onetime::Operations::Memberships::EntitlementOverride::ACTIONS.join(', ')
        }".freeze

        attr_reader :org, :customer, :entitlement, :action, :result

        def process_params
          @org_id      = sanitize_identifier(params['org_id'])
          # Email-tolerant (see AccountIdentifier) — sanitize_identifier strips
          # '@' and '.', which made the resolver's email arm unreachable.
          @member_id   = sanitize_account_identifier(params['member_id'])
          @entitlement = params['entitlement']&.to_s&.strip

          # Action comes from URL path:
          # - POST /entitlements/:action  -> params['action'] = 'grant' or 'revoke'
          # - DELETE /entitlements/overrides -> params['action'] = nil (literal path, not param)
          url_action = params['action']&.to_s&.downcase
          @action    = url_action.to_s.empty? ? 'clear' : url_action

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?
          raise_form_error('Member ID is required', field: :member_id) if @member_id.to_s.empty?

          unless Onetime::Operations::Memberships::EntitlementOverride::ACTIONS.include?(@action)
            raise_form_error(VALID_ACTIONS_MESSAGE, field: :action)
          end

          if @action != 'clear' && @entitlement.to_s.empty?
            raise_form_error('Entitlement is required for grant/revoke', field: :entitlement)
          end

          # Clear ignores any client-sent entitlement; drop it here so the
          # response contract holds (`entitlement` is null on clear) instead of
          # echoing back an input the operation never read.
          @entitlement = nil if @action == 'clear'
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @org = resolve_org(@org_id)
          raise_not_found('Organization not found') unless @org&.exists?

          @customer = resolve_customer(@member_id)
          raise_not_found('Member not found') unless @customer

          # TIER 2 (#4326), ALL arms. The URL carries the member's extid; the
          # confirmation is their EMAIL.
          guard_destructive_action!(
            tier: :sensitive,
            confirm_with: account_confirm_token(@customer),
            confirm_subject: "the member's email address",
            field: :member_id,
          )

          warn_unknown_entitlement
        end

        def process
          @result = Onetime::Operations::Memberships::EntitlementOverride.new(
            org: @org,
            customer: @customer,
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
              org_id: @org.extid,
              member_id: @customer.extid,
              entitlement: @entitlement,
              action: action_past_tense,
              effective_entitlements: @result.effective,
              grants: @result.grants,
              revokes: @result.revokes,
            },
          }
        end

        private

        # Warn but don't block — allows granting future entitlements. Only
        # grant/revoke reach the log line (clear returns first), so the verb is a
        # two-way pick; @org is resolved by now, so log its extid rather than the
        # raw request param. Advisory, not a guard: it runs after the
        # confirmation gate.
        def warn_unknown_entitlement
          return if @action == 'clear'
          return if Onetime::Operations::Memberships::EntitlementOverride.known_entitlement?(@entitlement)

          verb = @action == 'grant' ? 'Granting' : 'Revoking'
          OT.info "[colonel] #{verb} unknown entitlement '#{@entitlement}' for member #{@customer.extid} in org #{@org.extid}"
        end

        # :invalid_action / :missing_entitlement are a defensive backstop —
        # process_params already rejects both ahead of the call. :not_found is
        # LIVE: the org and customer both resolve but no active membership
        # joins them, which only the op can see.
        #
        # :no_change is a successful, idempotent 200 — the entitlement is already
        # in the requested state, so the response below describes reality.
        def handle_result_status(result)
          case result.status
          when :invalid_action
            raise_form_error(VALID_ACTIONS_MESSAGE, field: :action)
          when :missing_entitlement
            raise_form_error('Entitlement is required for grant/revoke', field: :entitlement)
          when :not_found
            raise_not_found('Membership not found')
          end
        end

        def action_past_tense
          ACTION_PAST_TENSE[@action]
        end
      end
    end
  end
end
