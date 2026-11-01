# apps/api/colonel/logic/colonel/set_user_default_organization.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'membership_resolvers'
require 'onetime/operations/customers/set_default_organization'

module ColonelAPI
  module Logic
    module Colonel
      # Change a customer's default organization.
      #
      # POST /api/colonel/users/:user_id/default-organization
      # Body: { "organization_id": "<org extid>", "reason": "..." }
      #
      # Thin adapter over {Onetime::Operations::Customers::SetDefaultOrganization}
      # (the single implementation, shared with `bin/ots customers
      # set-default-org`). The op enforces the rule — only an organization the
      # customer is an active member of, and not an archived one — and records
      # the ColonelAuditEvent, refusals included (CONTRACT 4). This class
      # resolves identifiers, gates, and shapes the response.
      #
      # TIER 2 (#4326): it changes where the customer lands, so the operator
      # echoes the target's email in X-OTS-Confirm, the same token as the other
      # /users/:user_id verbs (SetUserRole). It grants no access and the same
      # verb reverses it, so it is not elevation-gated.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class SetUserDefaultOrganization < ColonelAPI::Logic::Base
        include MembershipResolvers

        attr_reader :user_id, :organization_id, :user, :organization, :reason, :result

        def process_params
          # Email-tolerant, like every /users/:user_id verb. See AccountIdentifier.
          @user_id         = sanitize_account_identifier(params['user_id'])
          @organization_id = sanitize_identifier(params['organization_id'])
          # OPTIONAL operator-supplied why (#4338).
          @reason          = operator_reason_param

          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
          raise_form_error('Organization is required', field: :organization_id) if organization_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # extid, then email, then objid (AccountIdentifier#resolve_account).
          @user = resolve_customer(user_id)
          raise_not_found('User not found') unless user&.exists?
          raise_form_error('Cannot modify anonymous user', field: :user_id) if user.anonymous?

          # extid, then objid (MembershipResolvers#resolve_org).
          @organization = resolve_org(organization_id)
          raise_not_found('Organization not found') unless organization&.exists?

          # TIER 2 (#4326). The URL carries the extid; the confirmation is the
          # target's EMAIL.
          guard_destructive_action!(
            tier: :sensitive,
            confirm_with: account_confirm_token(user),
            confirm_subject: "the target account's email address",
            field: :user_id,
          )
        end

        def process
          @result = Onetime::Operations::Customers::SetDefaultOrganization.new(
            customer: user,
            organization: organization,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            reason: reason,
          ).call

          handle_result_status

          OT.info "[SetUserDefaultOrganization] user=#{user.extid} org=#{organization.extid} " \
                  "status=#{result.status}"

          success_data
        end

        def success_data
          {
            record: {
              extid: user.extid,
              default_organization: organization_summary(organization),
            },
            details: {
              previous_default_organization: organization_summary(result.previous),
            },
          }
        end

        private

        # The op already recorded the refusal; these are the console's 422s.
        # The `else` arm makes a status added to the op fail loudly here rather
        # than read as a success.
        def handle_result_status
          case result.status
          when :success, :no_change then nil
          when :not_member
            raise_form_error(
              'The customer is not an active member of that organization. ' \
              'Only an organization they already belong to can be their default.',
              field: :organization_id,
            )
          when :archived
            raise_form_error('That organization is archived and cannot be a default.', field: :organization_id)
          when :anonymous
            raise_form_error('Cannot modify anonymous user', field: :user_id)
          else
            raise_form_error(
              "Default organization change did not complete (#{result.status})",
              field: :organization_id,
            )
          end
        end

        def organization_summary(org)
          return nil if org.nil?

          { extid: org.extid, display_name: org.display_name }
        end
      end
    end
  end
end
