# apps/api/colonel/logic/colonel/add_membership.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/memberships/add'

module ColonelAPI
  module Logic
    module Colonel
      # Add a member to an organization (Colonel) — #3731.
      #
      # POST /api/colonel/organizations/:org_id/members
      # Body: { "customer": "user@example.com", "role": "admin" }
      #
      # Thin adapter over {Onetime::Operations::Memberships::Add} — the single,
      # audited, entitlement-materializing implementation. The OP owns the
      # AdminAuditEvent (do NOT audit here).
      #
      # The customer must already have an account (this endpoint does not create
      # invitations — that is the invite flow's job).
      #
      # Security invariant: BOTH the router (role=colonel) AND this logic
      # (verify_one_of_roles!) enforce the colonel role.
      class AddMembership < ColonelAPI::Logic::Base
        attr_reader :org, :customer, :role, :result

        def process_params
          @org_id      = sanitize_identifier(params['org_id'])
          @customer_id = sanitize_identifier(params['customer'])
          @role        = sanitize_plain_text(params['role']).to_s.downcase
          @role        = 'member' if @role.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?
          raise_form_error('Customer is required', field: :customer) if @customer_id.to_s.empty?

          @org = resolve_org(@org_id)
          raise_not_found('Organization not found') unless @org&.exists?

          @customer = resolve_customer(@customer_id)
          raise_not_found('Customer not found') unless @customer
        end

        def process
          @result = Onetime::Operations::Memberships::Add.new(
            org: org,
            customer: customer,
            role: role,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
          ).call

          handle_result_status

          OT.info "[AddMembership] org=#{org.extid} member=#{customer.extid} " \
                  "status=#{result.status} role=#{result.role}"

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
          return unless result.status == :invalid_role

          raise_form_error(
            "Invalid role '#{role}'. Must be one of: #{Onetime::Operations::Memberships::Add::VALID_ROLES.join(', ')}",
            field: :role,
          )
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
