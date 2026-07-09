# apps/api/colonel/logic/colonel/purge_user.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'auth/operations/customers/purge'

module ColonelAPI
  module Logic
    module Colonel
      # Purge (permanently delete) a single user.
      #
      # Thin adapter over Auth::Operations::Customers::Purge (which reuses
      # Auth::Operations::DeleteCustomer and records the AdminAuditEvent). This
      # class only handles HTTP concerns.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class PurgeUser < ColonelAPI::Logic::Base
        attr_reader :user_id, :user, :purged_extid, :purged_objid

        def process_params
          @user_id = sanitize_identifier(params['user_id'])
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

          raise_form_error('Cannot purge anonymous user', field: :user_id) if user.anonymous?
          raise_form_error('Cannot purge your own account', field: :user_id) if user.objid == cust.objid
        end

        def process
          # Capture identity before the record is destroyed.
          @purged_extid = user.extid
          @purged_objid = user.objid

          Auth::Operations::Customers::Purge.new(
            customer: user,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
          ).call

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
      end
    end
  end
end
