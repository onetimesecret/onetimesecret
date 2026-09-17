# apps/api/colonel/logic/colonel/purge_user.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'
require 'auth/operations/customers/purge'
require 'onetime/operations/customers/role_support'

module ColonelAPI
  module Logic
    module Colonel
      # Purge (permanently delete) a single user.
      #
      # Thin adapter over Auth::Operations::Customers::Purge (which reuses
      # Auth::Operations::DestroyCustomerRecord and records the ColonelAuditEvent). This
      # class only handles HTTP concerns.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class PurgeUser < ColonelAPI::Logic::Base
        include AccountIdentifier

        attr_reader :user_id, :user, :purged_extid, :purged_objid, :reason, :result

        def process_params
          # sanitize_account_identifier (NOT sanitize_identifier) — the latter
          # strips '@' and '.', which silently destroyed the documented email
          # arm below. See AccountIdentifier.
          @user_id = sanitize_account_identifier(params['user_id'])
          # OPTIONAL operator-supplied why (#4338) — query string, since this is
          # a DELETE. See ColonelAPI::Logic::Base#operator_reason_param.
          @reason  = operator_reason_param
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve by PUBLIC id (extid) first — the users list exposes only
          # extid, so every admin surface routes by it — then email, then objid.
          # Mirrors Auth::Operations::Customers::Show#resolve (show.rb): a plain
          # Customer.load only resolves the internal objid, so an extid would 404.
          @user = resolve_account(user_id)
          raise_not_found('User not found') unless user&.exists?

          raise_form_error('Cannot purge anonymous user', field: :user_id) if user.anonymous?

          # TIER 1 (#4326). The URL carries the extid; the confirmation is the
          # account's EMAIL (its extid only when it has none), so a scraped-id
          # replay must also know an identifier the URL never carried.
          guard_destructive_action!(
            tier: :destructive,
            confirm_with: account_confirm_token(user),
            confirm_subject: 'the account email address (or its external id when it has none)',
            field: :user_id,
          )

          # INTERLOCK — after proof (guard order §0.2): a 422 here would
          # otherwise tell a caller who has proven nothing whether the named
          # account is their own.
          raise_form_error('Cannot purge your own account', field: :user_id) if user.objid == cust.objid

          # INTERLOCK (#4328): purging the last active colonel deletes the last
          # administrator — a HARDER lockout than demote/unverify (the account is
          # gone, not merely stripped) and, being irreversible, one this op cannot
          # post-write roll back the way SetRole/SetVerification do. Refuse it at
          # the pre-check. An UNVERIFIED colonel-role target is not an active
          # colonel (last_colonel_by_verification? requires verified?), so purging
          # it cannot empty the roster and is allowed. The residual concurrent
          # double-purge (two colonels purging each other past this non-atomic
          # check) cannot be undone here — a purged account cannot be recreated —
          # and is the one gap purge's irreversibility leaves that the reversible
          # verbs close with a post-write rollback.
          if Onetime::Operations::Customers::RoleSupport.last_colonel_by_verification?(user)
            raise_form_error(
              'Refusing to purge the last active colonel: it would leave the install ' \
              'with no administrator (recoverable only from the CLI). Promote and ' \
              'verify another colonel first.',
              field: :user_id,
            )
          end

          charge_destructive_budget!
        end

        def process
          # Capture identity before the record is destroyed.
          @purged_extid = user.extid
          @purged_objid = user.objid

          @result = Auth::Operations::Customers::Purge.new(
            customer: user,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            reason: reason,
            # Single-account operator action: affordable, and the global sweep
            # catches references the customer's own indexes do not point at.
            deep: true,
          ).call

          OT.info "[PurgeUser] user=#{purged_extid} status=#{result.status}"

          handle_result_status
          success_data
        end

        def success_data
          {
            record: {
              deleted: true,
              user_id: purged_objid,
              extid: purged_extid,
            },
            details: purge_result_payload.merge(
              message: 'User purged successfully',
            ),
          }
        end

        private

        def handle_result_status
          case result.status
          when :success
            nil
          when :refused
            raise_form_error(
              'Purge refused. Resolve the reported blockers and retry.',
              field: :user_id,
              error_type: :conflict,
              details: purge_result_payload,
            )
          when :partial
            raise_form_error(
              'Purge stopped after mutation began. Review the completed stages before retrying.',
              field: :user_id,
              error_type: :partial,
              details: purge_result_payload,
            )
          when :not_found
            raise_not_found('User not found')
          else
            raise_form_error(
              "Purge did not complete (#{result.status})",
              field: :user_id,
              error_type: :system_error,
              details: purge_result_payload,
            )
          end
        end

        def purge_result_payload
          {
            status: result.status,
            deleted: result.status == :success,
            extid: result.extid,
            custid: result.custid,
            blockers: result.blockers,
            actions: result.actions,
            planned_actions: result.planned_actions,
            stage: result.stage,
            completed_stages: result.completed_stages,
          }
        end
      end
    end
  end
end
