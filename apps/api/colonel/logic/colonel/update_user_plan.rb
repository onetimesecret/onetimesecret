# apps/api/colonel/logic/colonel/update_user_plan.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../apps/web/billing/lib/billing_service'
require 'auth/operations/customers/set_plan'

module ColonelAPI
  module Logic
    module Colonel
      # Updates a user's plan with catalog validation.
      #
      # Thin adapter over Auth::Operations::Customers::SetPlan (the single
      # implementation). This class handles HTTP concerns (param sanitization,
      # authorization, catalog validation, response shape); the op performs the
      # mutation AND records the AdminAuditEvent — so a plan change is audited
      # like every other mutating admin verb (epic #20 CONTRACT 4).
      #
      # Validates that the requested plan_id exists in the billing catalog
      # before allowing the update, preventing invalid plan assignments.
      #
      class UpdateUserPlan < ColonelAPI::Logic::Base
        attr_reader :user_id, :user, :new_planid, :old_planid, :change_status

        def process_params
          @user_id    = sanitize_identifier(params['user_id'])
          @new_planid = sanitize_identifier(params['planid'])

          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
          raise_form_error('Plan ID is required', field: :planid) if new_planid.to_s.empty?
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

          # Validate plan_id exists in catalog
          return if Billing::BillingService.valid_plan_id?(new_planid)

          raise_form_error(
            "Invalid plan ID '#{new_planid}'. Plan must exist in billing catalog or config.",
            field: :planid,
          )
        end

        def process
          @old_planid = user.planid

          result         = Auth::Operations::Customers::SetPlan.new(
            customer: user,
            planid: new_planid,
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
              old_planid: old_planid,
              new_planid: user.planid,
              updated: user.updated,
            },
            details: {
              changed: change_status == :success,
              message: 'User plan updated successfully',
            },
          }
        end
      end
    end
  end
end
