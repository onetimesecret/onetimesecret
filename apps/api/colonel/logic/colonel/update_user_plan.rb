# apps/api/colonel/logic/colonel/update_user_plan.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../apps/web/billing/lib/billing_service'

module ColonelAPI
  module Logic
    module Colonel
      # Updates a user's plan with catalog validation
      #
      # Validates that the requested plan_id exists in the billing catalog
      # before allowing the update, preventing invalid plan assignments.
      #
      class UpdateUserPlan < ColonelAPI::Logic::Base
        attr_reader :user_id, :user, :new_planid, :old_planid

        def process_params
          @user_id    = params['user_id']
          @new_planid = params['planid']

          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
          raise_form_error('Plan ID is required', field: :planid) if new_planid.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @user = Onetime::Customer.load(user_id)
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

          # Update the user's plan
          user.planid = new_planid
          user.save

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
              message: 'User plan updated successfully',
            },
          }
        end
      end
    end
  end
end
