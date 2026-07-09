# apps/api/colonel/logic/colonel/set_user_suspension.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'auth/operations/customers/set_suspension'

module ColonelAPI
  module Logic
    module Colonel
      # Base for the colonel suspend / unsuspend endpoints — the trust & safety
      # "pause button" (reversible, destroys no data; contrast PurgeUser).
      #
      # Thin adapter over Auth::Operations::Customers::SetSuspension (the single
      # implementation). The op performs the mutation, revokes the customer's
      # readable sessions, AND records the AdminAuditEvent — this class only
      # handles HTTP concerns (param sanitization, authorization, response
      # shape). Subclasses only choose the target state.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class SetUserSuspensionBase < ColonelAPI::Logic::Base
        attr_reader :user_id, :user, :reason, :change_result, :sessions_revoked

        # @return [Boolean] target suspension state (subclass overrides)
        def suspended_target
          raise NotImplementedError
        end

        def process_params
          @user_id = sanitize_identifier(params['user_id'])
          @reason  = sanitize_plain_text(params['reason'], max_length: 255) if params['reason']
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
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

          # Privilege guard (UX-level; the op enforces it again as a backstop):
          # colonel accounts cannot be suspended — demote the role first.
          return unless suspended_target && user.role?('colonel')

          raise_form_error('Colonel accounts cannot be suspended. Demote the role first.', field: :user_id)
        end

        def process
          result = Auth::Operations::Customers::SetSuspension.new(
            customer: user,
            suspended: suspended_target,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            reason: reason,
          ).call
          @change_result    = result.status
          @sessions_revoked = result.sessions_revoked

          success_data
        rescue Auth::Operations::Customers::SetSuspension::PrivilegedAccount => ex
          raise_form_error(ex.message, field: :user_id)
        end

        def success_data
          {
            record: {
              user_id: user.objid,
              extid: user.extid,
              email: user.obscure_email,
              suspended: user.suspended?,
              updated: user.updated,
            },
            details: {
              changed: change_result == :success,
              sessions_revoked: sessions_revoked,
              message: suspended_target ? 'User suspended' : 'User unsuspended',
            },
          }
        end
      end

      # POST /users/:user_id/suspend
      class SuspendUser < SetUserSuspensionBase
        def suspended_target
          true
        end
      end

      # POST /users/:user_id/unsuspend
      class UnsuspendUser < SetUserSuspensionBase
        def suspended_target
          false
        end
      end
    end
  end
end
