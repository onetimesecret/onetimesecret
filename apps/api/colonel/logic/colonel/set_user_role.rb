# apps/api/colonel/logic/colonel/set_user_role.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'
require 'auth/operations/customers/set_role'
require 'onetime/operations/customers/role_support'

module ColonelAPI
  module Logic
    module Colonel
      # Change a user's role (colonel / admin / staff / customer).
      #
      # Thin adapter over Auth::Operations::Customers::SetRole (the single
      # implementation). The op performs the mutation AND records the
      # ColonelAuditEvent — this class only handles HTTP concerns (param
      # sanitization, authorization, response shape).
      #
      # ## No dry_run (#4328)
      #
      # `dry_run` is pinned false here, matching transfer_organization_ownership.rb:
      # the console has no preview flow for role changes, and adding one would be
      # a UI feature this epic does not scope. The defect the issue names — a
      # one-click privilege change — is answered by typed confirmation, step-up
      # elevation and the interlocks below, not by a preview.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class SetUserRole < ColonelAPI::Logic::Base
        include AccountIdentifier

        attr_reader :user_id, :user, :new_role, :reason, :old_role, :change_status

        def process_params
          # sanitize_account_identifier (NOT sanitize_identifier) — the latter
          # strips '@' and '.', so an email identifier arrived as
          # `userexamplecom` and this endpoint 404'd on every address an
          # operator pasted. See AccountIdentifier.
          @user_id  = sanitize_account_identifier(params['user_id'])
          @new_role = sanitize_plain_text(params['role'])
          # OPTIONAL operator-supplied why (#4338). See
          # ColonelAPI::Logic::Base#operator_reason_param.
          @reason   = operator_reason_param

          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
          raise_form_error('Role is required', field: :role) if new_role.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve by PUBLIC id (extid) first — the users list exposes only
          # extid, so every admin surface routes by it — then email, then objid.
          # Mirrors Auth::Operations::Customers::Show#resolve (show.rb): a plain
          # Customer.load only resolves the internal objid, so an extid would 404.
          @user = resolve_account(user_id)
          raise_not_found('User not found') unless user&.exists?

          raise_form_error('Cannot modify anonymous user', field: :user_id) if user.anonymous?

          unless Auth::Operations::Customers::SetRole::VALID_ROLES.include?(new_role)
            raise_form_error(
              "Invalid role '#{new_role}'. Valid roles: " \
              "#{Auth::Operations::Customers::SetRole::VALID_ROLES.join(', ')}",
              field: :role,
            )
          end

          # TIER 1 (#4326). The URL carries the extid; the confirmation is the
          # target's EMAIL, so a scraped-id replay needs a second identifier.
          guard_destructive_action!(
            tier: :destructive,
            confirm_with: account_confirm_token(user),
            confirm_subject: "the target account's email address",
            field: :user_id,
          )

          enforce_role_interlocks!

          charge_destructive_budget!
        end

        def process
          @old_role = user.role

          result         = Auth::Operations::Customers::SetRole.new(
            customer: user,
            role: new_role,
            actor: cust.extid,       # acting colonel's PUBLIC id (never an objid)
            actor_objid: cust.objid, # INTERNAL id, for the self-demotion check only
            reason: reason,          # optional operator-supplied why (#4338)
          ).call
          @change_status = result.status

          handle_change_status

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

        private

        # STEP 4 of the guard-order contract (logic/destructive_action.rb).
        # These run AFTER elevation + confirmation so a caller holding only the
        # cookie cannot use the 422s to learn who the last colonel is, or
        # whether a given account is their own.
        #
        # Both refusals are ALSO enforced by the op (shared with
        # `bin/ots customers role demote`, which has no HTTP layer to put them
        # in); these adapter checks exist so the console gets a friendly,
        # remediation-naming 422 rather than a bare status — exactly as
        # set_user_suspension.rb does for its privilege guard. The op remains
        # the backstop, and #handle_change_status maps it if it ever wins.
        def enforce_role_interlocks!
          if user.objid == cust.objid && new_role != 'colonel'
            raise_form_error(
              'Cannot demote your own colonel account. Have another colonel demote you, ' \
              'or use `bin/ots customers role demote`.',
              field: :user_id,
            )
          end

          return unless Onetime::Operations::Customers::RoleSupport.last_colonel?(user, new_role)

          raise_form_error(
            'Cannot demote the last remaining colonel. Promote another account first.',
            field: :user_id,
          )
        end

        # Map the op's Result#status. The interlock statuses are reachable only
        # if the roster changed between raise_concerns and the mutation (or a
        # future caller skips the adapter checks), so they answer the same 422s
        # rather than a silent success. The `else` arm exists so a status added
        # to the op fails loudly here instead of being reported as "changed".
        def handle_change_status
          case change_status
          when :success, :no_change then nil
          when :self_demotion
            raise_form_error('Cannot demote your own colonel account.', field: :user_id)
          when :last_colonel
            raise_form_error('Cannot demote the last remaining colonel.', field: :user_id)
          else
            raise_form_error("Role change did not complete (#{change_status})", field: :role)
          end
        end
      end
    end
  end
end
