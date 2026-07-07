# apps/api/colonel/logic/colonel/set_user_verification.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'auth/operations/customers/set_verification'

module ColonelAPI
  module Logic
    module Colonel
      # Base for the colonel verify / unverify endpoints.
      #
      # Thin adapter over Auth::Operations::Customers::SetVerification, which
      # reuses the incumbent Auth::Operations::SetCustomerVerification (cross-store
      # Redis+SQL writer) and records the AdminAuditEvent. Subclasses only choose
      # the target state.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class SetUserVerificationBase < ColonelAPI::Logic::Base
        attr_reader :user_id, :user, :change_result

        # @return [Boolean] target verification state (subclass overrides)
        def verified_target
          raise NotImplementedError
        end

        # Provenance tag written to the customer's verified_by field.
        def verified_by_tag
          verified_target ? 'colonel_admin' : nil
        end

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

          raise_form_error('Cannot modify anonymous user', field: :user_id) if user.anonymous?
        end

        def process
          @change_result = Auth::Operations::Customers::SetVerification.new(
            customer: user,
            verified: verified_target,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            verified_by: verified_by_tag,
          ).call

          success_data
        rescue Auth::Operations::SetCustomerVerification::NoAuthDatabase => ex
          raise_form_error("#{ex.message}. Check AUTH_DATABASE_URL.")
        rescue Auth::Operations::SetCustomerVerification::AccountNotFound => ex
          raise_not_found("#{ex.message}. Run auth-account reconciliation.")
        end

        def success_data
          {
            record: {
              user_id: user.objid,
              extid: user.extid,
              email: user.obscure_email,
              verified: user.verified?,
              updated: user.updated,
            },
            details: {
              changed: change_result == :success,
              message: verified_target ? 'User verified' : 'User unverified',
            },
          }
        end
      end

      # POST /users/:user_id/verify
      class VerifyUser < SetUserVerificationBase
        def verified_target
          true
        end
      end

      # POST /users/:user_id/unverify
      class UnverifyUser < SetUserVerificationBase
        def verified_target
          false
        end
      end
    end
  end
end
