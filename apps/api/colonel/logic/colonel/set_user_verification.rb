# apps/api/colonel/logic/colonel/set_user_verification.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'
require 'auth/operations/customers/set_verification'
require 'onetime/operations/customers/role_support'

module ColonelAPI
  module Logic
    module Colonel
      # Base for the colonel verify / unverify endpoints.
      #
      # Thin adapter over Auth::Operations::Customers::SetVerification, which
      # reuses the incumbent Auth::Operations::SetCustomerVerification (cross-store
      # Redis+SQL writer) and records the ColonelAuditEvent. Subclasses only choose
      # the target state.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class SetUserVerificationBase < ColonelAPI::Logic::Base
        include AccountIdentifier

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

          raise_form_error('Cannot modify anonymous user', field: :user_id) if user.anonymous?

          # Only the UNVERIFY arm is gated (#4326, TIER 2): has_system_role?
          # refuses every elevated role to an unverified account, so unverifying
          # strips colonel eligibility. VerifyUser is the restorative arm and
          # stays un-gated — this one `return` guards the gate AND the interlocks
          # below, so a refactor that hoists either above it would gate recovery.
          return if verified_target

          guard_destructive_action!(
            tier: :sensitive,
            confirm_with: account_confirm_token(user),
            confirm_subject: "the target account's email address",
            field: :user_id,
          )

          enforce_unverify_interlocks!
        end

        def process
          @change_result = Auth::Operations::Customers::SetVerification.new(
            customer: user,
            verified: verified_target,
            actor: cust.extid,       # acting colonel's PUBLIC id (never an objid)
            actor_objid: cust.objid, # INTERNAL id, for the self-unverify check only
            verified_by: verified_by_tag,
          ).call

          handle_change_result

          success_data
        rescue Auth::Operations::SetCustomerVerification::NoAuthDatabase => ex
          raise_form_error("#{ex.message}. Check AUTH_DATABASE_URL.")
        rescue Auth::Operations::SetCustomerVerification::AccountNotFound => ex
          raise_not_found("#{ex.message}. Run auth-account reconciliation.")
        rescue Auth::Operations::SetCustomerVerification::AccountClosed => ex
          raise_form_error(ex.message)
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

        private

        # STEP 4 of the guard-order contract (logic/destructive_action.rb), and
        # unverify-only by construction (the caller returns on the verify arm).
        #
        # Unverifying a colonel is a demotion by another name: has_system_role?
        # refuses every elevated role to an unverified account. Without these,
        # an attacker refused a demotion by RoleSupport.last_colonel? would
        # simply call unverify instead. After proof, so the 422s cannot be used
        # as a "who is the last colonel" oracle. The op enforces both again for
        # `bin/ots customers unverify`.
        def enforce_unverify_interlocks!
          if user.objid == cust.objid
            raise_form_error(
              'Cannot unverify your own account: verification is required to hold the ' \
              'colonel role. Have another colonel do it, or use the CLI.',
              field: :user_id,
            )
          end

          return unless Onetime::Operations::Customers::RoleSupport.last_colonel_by_verification?(user)

          raise_form_error(
            'Cannot unverify the last remaining colonel — the install would have no ' \
            'administrator. Promote and verify another account first.',
            field: :user_id,
          )
        end

        # The op's symbol contract. The two interlock statuses are reachable only
        # if the roster changed between raise_concerns and the write; they answer
        # the same 422s rather than reporting a change that did not happen. The
        # `else` arm makes a status added to the op fail loudly here.
        def handle_change_result
          case change_result
          when :success, :no_change then nil
          when :self_unverify
            raise_form_error('Cannot unverify your own account.', field: :user_id)
          when :last_colonel
            raise_form_error('Cannot unverify the last remaining colonel.', field: :user_id)
          else
            raise_form_error("Verification change did not complete (#{change_result})", field: :user_id)
          end
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
