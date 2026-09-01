# apps/api/colonel/logic/colonel/purge_user.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'
require 'auth/operations/customers/purge'

module ColonelAPI
  module Logic
    module Colonel
      # Purge (permanently delete) a single user.
      #
      # Thin adapter over Auth::Operations::Customers::Purge (which reuses
      # Auth::Operations::DeleteCustomer and records the ColonelAuditEvent). This
      # class only handles HTTP concerns.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class PurgeUser < ColonelAPI::Logic::Base
        include AccountIdentifier

        attr_reader :user_id, :user, :purged_extid, :purged_objid, :result

        def process_params
          # sanitize_account_identifier (NOT sanitize_identifier) — the latter
          # strips '@' and '.', which silently destroyed the documented email
          # arm below. See AccountIdentifier.
          @user_id = sanitize_account_identifier(params['user_id'])
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

          charge_destructive_budget!
        end

        def process
          # Capture identity before the record is destroyed.
          @purged_extid = user.extid
          @purged_objid = user.objid

          @result = Auth::Operations::Customers::Purge.new(
            customer: user,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
          ).call

          handle_result_status

          OT.info "[PurgeUser] user=#{purged_extid} status=#{result.status}"

          success_data
        end

        def success_data
          {
            record: {
              deleted: true,
              user_id: purged_objid,
              extid: purged_extid,
            },
            details: {
              message: 'User purged successfully',
            },
          }
        end

        private

        # Purge::Result#status is a CLOSED contract (purge.rb): :success or
        # :not_found, nothing else.
        #
        # :not_found means DeleteCustomer found nothing to destroy — the record
        # vanished between raise_concerns and the destroy — and in that case the
        # op records NO ColonelAuditEvent. Reporting `deleted: true` would invent
        # both a deletion and an audit trail. The CLI peer (`bin/ots customers
        # purge-one`) applies the same discipline by exiting 1 on this status.
        #
        # The else arm exists so a future status added to the op fails loudly
        # here instead of being swallowed back into a success response.
        def handle_result_status
          case result.status
          when :success   then nil
          when :not_found then raise_not_found('User not found')
          else raise_form_error("Purge did not complete (#{result.status})", field: :user_id)
          end
        end
      end
    end
  end
end
