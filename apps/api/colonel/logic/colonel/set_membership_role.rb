# apps/api/colonel/logic/colonel/set_membership_role.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'membership_resolvers'
require 'onetime/operations/memberships/set_role'

module ColonelAPI
  module Logic
    module Colonel
      # Set an organization member's role (Colonel) — #3731.
      #
      # POST /api/colonel/organizations/:org_id/members/:member_id/role
      # Body: { "role": "admin" }
      #
      # Thin adapter over {Onetime::Operations::Memberships::SetRole} — the single,
      # audited, entitlement-materializing implementation. This class resolves the
      # org + member and maps the op's Result status to an HTTP outcome. The OP
      # owns the AdminAuditEvent (do NOT audit here — that would double-record).
      #
      # Security invariant: BOTH the router (role=colonel) AND this logic
      # (verify_one_of_roles!) enforce the colonel role.
      class SetMembershipRole < ColonelAPI::Logic::Base
        include MembershipResolvers

        attr_reader :org, :customer, :new_role, :result

        def process_params
          @org_id    = sanitize_identifier(params['org_id'])
          @member_id = sanitize_identifier(params['member_id'])
          @new_role  = sanitize_plain_text(params['role']).to_s.downcase
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
          @result = Onetime::Operations::Memberships::SetRole.new(
            org: org,
            customer: customer,
            new_role: new_role,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
          ).call

          handle_result_status

          OT.info "[SetMembershipRole] org=#{org.extid} member=#{customer.extid} " \
                  "status=#{result.status} #{result.from}->#{result.to}"

          success_data
        end

        def success_data
          {
            record: {
              org_id: org.extid,
              member_id: customer.extid,
              status: result.status.to_s,
              from: result.from,
              to: result.to,
            },
          }
        end

        private

        # Non-success statuses that mutate nothing are surfaced as 4xx form errors;
        # :no_change is an idempotent 200 (already at the target role).
        def handle_result_status
          case result.status
          when :invalid_role
            raise_form_error(
              "Invalid role '#{new_role}'. Must be one of: #{Onetime::Operations::Memberships::SetRole::VALID_ROLES.join(', ')}",
              field: :role,
            )
          when :not_found
            raise_not_found('Membership not found')
          when :last_owner
            raise_form_error('Cannot demote the last remaining owner of the organization', field: :role)
          end
        end
      end
    end
  end
end
