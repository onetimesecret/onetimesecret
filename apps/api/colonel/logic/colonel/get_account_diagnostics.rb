# apps/api/colonel/logic/colonel/get_account_diagnostics.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'

require 'auth/operations/customers/diagnose'

module ColonelAPI
  module Logic
    module Colonel
      # Get Account Diagnostics
      #
      # @api Returns the read-only "why can't this user log in / sign up"
      #   read-out for one account: customer record state, Rodauth account
      #   status, lockout and login failures, verification / reset keys, MFA,
      #   active sessions, the authentication audit log tail, and the login
      #   rate limiter — plus a derived findings list a support agent can act
      #   on directly. Thin adapter over Auth::Operations::Customers::Diagnose
      #   (the single implementation, shared with `bin/ots customers
      #   diagnose`). Mutates nothing, records no audit event. Requires
      #   colonel role.
      class GetAccountDiagnostics < ColonelAPI::Logic::Base
        include AccountIdentifier

        SCHEMAS = { response: 'colonelAccountDiagnostics' }.freeze

        attr_reader :user_id, :user, :result

        def process_params
          # sanitize_account_identifier — NOT sanitize_identifier, which strips
          # '@' and '.' and would destroy the email arm (see AccountIdentifier).
          @user_id = sanitize_account_identifier(params['user_id'])
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve extid -> email -> objid like GetUserDetails, but a missing
          # customer is NOT a 404 when the identifier is an email: an auth
          # account without a customer record (or nothing at all — "check the
          # other regions") is itself a diagnosis, and this endpoint's job is
          # to say so.
          @user = resolve_account(user_id)
          raise_not_found('User not found') unless user&.exists? || user_id.include?('@')
        end

        def process
          @result = Auth::Operations::Customers::Diagnose.new(
            identifier: user_id,
            customer: user,
            audit_log_limit: audit_log_limit,
          ).call

          success_data
        end

        # Overrides success_data WITHOUT super (same as GetBrandDiagnostics):
        # the Base custid->user_id transform has nothing to rename here. The
        # `record` block mirrors the identity summary the detail page already
        # holds; the diagnosis itself lives under `details`.
        def success_data
          {
            record: {
              identifier: user_id,
              found: result.found?,
            },
            details: {
              findings: result.findings,
              sections: result.sections,
            },
          }
        end

        private

        def audit_log_limit
          limit = params['audit_limit'].to_i
          limit.positive? ? limit : Auth::Operations::Customers::Diagnose::DEFAULT_AUDIT_LOG_LIMIT
        end
      end
    end
  end
end
