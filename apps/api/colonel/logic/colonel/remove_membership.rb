# apps/api/colonel/logic/colonel/remove_membership.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/memberships/remove'

module ColonelAPI
  module Logic
    module Colonel
      # Remove a member from an organization (Colonel) — #3731.
      #
      # DELETE /api/colonel/organizations/:org_id/members/:member_id
      #
      # Thin adapter over {Onetime::Operations::Memberships::Remove} — the single,
      # audited implementation. It tears down the membership and clears the
      # member's materialized entitlements. The OP owns the AdminAuditEvent (do
      # NOT audit here).
      #
      # MUTATING + destructive; the colonel UI guards it behind a typed
      # confirmation client-side. The sole-owner guardrail lives in the op.
      #
      # Security invariant: BOTH the router (role=colonel) AND this logic
      # (verify_one_of_roles!) enforce the colonel role.
      class RemoveMembership < ColonelAPI::Logic::Base
        attr_reader :org, :customer, :result

        def process_params
          @org_id    = sanitize_identifier(params['org_id'])
          @member_id = sanitize_identifier(params['member_id'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?
          raise_form_error('Member ID is required', field: :member_id) if @member_id.to_s.empty?

          @org = resolve_org(@org_id)
          raise_not_found('Organization not found') unless @org&.exists?

          @customer = resolve_customer(@member_id)
          raise_not_found('Member not found') unless @customer
        end

        def process
          @result = Onetime::Operations::Memberships::Remove.new(
            org: org,
            customer: customer,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
          ).call

          handle_result_status

          OT.info "[RemoveMembership] org=#{org.extid} member=#{customer.extid} status=#{result.status}"

          success_data
        end

        def success_data
          {
            record: {
              org_id: org.extid,
              member_id: customer.extid,
              status: result.status.to_s,
              role: result.role,
            },
          }
        end

        private

        def handle_result_status
          case result.status
          when :not_found
            raise_not_found('Membership not found')
          when :last_owner
            raise_form_error('Cannot remove the last remaining owner of the organization', field: :member_id)
          end
        end

        def resolve_org(identifier)
          Onetime::Organization.find_by_extid(identifier) ||
            Onetime::Organization.load(identifier)
        end

        def resolve_customer(identifier)
          Onetime::Customer.load_by_extid_or_email(OT::Utils.normalize_email(identifier))
        end
      end
    end
  end
end
