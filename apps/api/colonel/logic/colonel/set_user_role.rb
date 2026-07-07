# apps/api/colonel/logic/colonel/set_user_role.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'auth/operations/customers/set_role'

module ColonelAPI
  module Logic
    module Colonel
      # Change a user's role (colonel / admin / staff / customer).
      #
      # Thin adapter over Auth::Operations::Customers::SetRole (the single
      # implementation). The op performs the mutation AND records the
      # AdminAuditEvent — this class only handles HTTP concerns (param
      # sanitization, authorization, response shape).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class SetUserRole < ColonelAPI::Logic::Base
        attr_reader :user_id, :user, :new_role, :old_role, :change_status

        def process_params
          @user_id  = sanitize_identifier(params['user_id'])
          @new_role = sanitize_plain_text(params['role'])

          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
          raise_form_error('Role is required', field: :role) if new_role.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve by PUBLIC id (extid) first — the users list exposes only
          # extid, so every admin surface routes by it — then email, then objid.
          # Mirrors Auth::Operations::Customers::Show#resolve (show.rb): a plain
          # Customer.load only resolves the internal objid, so an extid would 404.
          @user = Onetime::Customer.load_by_extid_or_email(user_id) ||
                  Onetime::Customer.load(user_id)
          raise_not_found('User not found') unless user&.exists?

          raise_form_error('Cannot modify anonymous user', field: :user_id) if user.anonymous?

          return if Auth::Operations::Customers::SetRole::VALID_ROLES.include?(new_role)

          raise_form_error(
            "Invalid role '#{new_role}'. Valid roles: " \
            "#{Auth::Operations::Customers::SetRole::VALID_ROLES.join(', ')}",
            field: :role,
          )
        end

        def process
          @old_role = user.role

          result = Auth::Operations::Customers::SetRole.new(
            customer: user,
            role: new_role,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
          ).call
          @change_status = result.status

          success_data
        end

        def success_data
          {
            record: {
              user_id: user.objid,
              extid: user.extid,
              email: user.obscure_email,
              old_role: old_role,
              new_role: user.role,
              updated: user.updated,
            },
            details: {
              changed: change_status == :success,
              message: 'User role updated successfully',
            },
          }
        end
      end
    end
  end
end
