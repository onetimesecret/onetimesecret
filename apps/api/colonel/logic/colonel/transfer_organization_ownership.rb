# apps/api/colonel/logic/colonel/transfer_organization_ownership.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'membership_resolvers'
require 'onetime/operations/org/transfer_ownership'

module ColonelAPI
  module Logic
    module Colonel
      # Transfer an organization's ownership (Colonel) — the console peer of
      # `bin/ots org transfer-ownership` (#3731 D33, filed as #3907).
      #
      # POST /api/colonel/organizations/:org_id/transfer-ownership
      # Body: { "new_owner": "user@example.com", "demote_to": "admin" }
      #
      # Thin adapter over {Onetime::Operations::Org::TransferOwnership} — the
      # single implementation of the transfer verb (promote-then-demote
      # ordering, legacy owner_id pivot, best-effort rollback). This class owns
      # only HTTP concerns: params, authorization, org/customer resolution and
      # the response shape.
      #
      # The OP records the single `organization.transfer_ownership`
      # AdminAuditEvent (plus the two composed `membership.set_role` events —
      # three per transfer, by design, D26). DO NOT audit here; a second event
      # would double-record the trail.
      #
      # The new owner MUST already be an active member (D28: one confirmation
      # must not both create a membership and hand it ownership) — :not_member
      # below tells the operator to add them first. This endpoint never
      # fabricates a Customer (ADR-023).
      #
      # No `?dry_run=1` preview (decision D12 precedent, reconcile_organization):
      # the op defaults to a dry run, but the admin UI has no preview flow
      # today, so this adapter pins `dry_run: false`.
      #
      # Security invariant: BOTH the router (role=colonel) AND this logic
      # (verify_one_of_roles!) enforce the colonel role.
      class TransferOrganizationOwnership < ColonelAPI::Logic::Base
        include MembershipResolvers

        attr_reader :org, :new_owner, :demote_to, :result

        def process_params
          @org_id       = sanitize_identifier(params['org_id'])
          # Email-tolerant (see AccountIdentifier) — sanitize_identifier strips
          # '@' and '.', which would make the resolver's email arm unreachable.
          @new_owner_id = sanitize_account_identifier(params['new_owner'])
          @demote_to    = sanitize_plain_text(params['demote_to']).to_s.downcase
          @demote_to    = 'admin' if @demote_to.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?
          raise_form_error('New owner is required', field: :new_owner) if @new_owner_id.to_s.empty?

          @org = resolve_org(@org_id)
          raise_not_found('Organization not found') unless @org&.exists?

          @new_owner = resolve_customer(@new_owner_id)
          raise_not_found('Customer not found') unless @new_owner
        end

        def process
          @result = Onetime::Operations::Org::TransferOwnership.new(
            org: org,
            new_owner: new_owner,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            demote_to: demote_to,
            # Pinned: no preview flow in the admin UI today (D12).
            dry_run: false,
          ).call

          handle_result_status

          OT.info "[TransferOrganizationOwnership] org=#{org.extid} to=#{new_owner.extid} " \
                  "status=#{result.status} demoted=#{result.demoted.size}"

          success_data
        end

        # PUBLIC extids only, matching the membership adapters (the op's Result
        # never carries an objid). Key names mirror the CLI's --json payload so
        # the two adapters cannot drift.
        def success_data
          {
            record: {
              org_id: org.extid,
              status: result.status.to_s,
              from_owner_id: result.from_owner_id,
              to_owner_id: result.to_owner_id,
              demoted: result.demoted,
              demoted_to: result.from_owner_role_after,
              orphaned_owner: result.orphaned_owner,
            },
          }
        end

        private

        # Non-OK statuses mutate nothing and surface as 4xx form errors;
        # :no_change is an idempotent 200 (already the sole owner). :planned
        # cannot occur here — dry_run is pinned false above.
        def handle_result_status
          case result.status
          when :not_member
            raise_form_error(
              'Customer is not an active member of the organization. Add them as a member first.',
              field: :new_owner,
            )
          when :invalid_role
            raise_form_error(
              "Invalid demote_to role '#{demote_to}'. Must be one of: " \
              "#{Onetime::Operations::Org::TransferOwnership::DEMOTABLE_ROLES.join(', ')}",
              field: :demote_to,
            )
          end
        end
      end
    end
  end
end
