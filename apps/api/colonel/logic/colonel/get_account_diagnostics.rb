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
          # customer is never a 404 here. "No customer record" is itself a
          # diagnosis: the identifier may still name an orphaned accounts row
          # (Diagnose looks one up by email, extid AND numeric Rodauth id), and
          # "nothing at all — check the other regions" is the answer support
          # needs, not a status code that withholds it. Same posture as
          # GetBrandDiagnostics, and the same answer `bin/ots customers
          # diagnose` gives. A nil `user` passes through so Diagnose owns the
          # orphan lookup.
          @user = resolve_account(user_id)
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
        #
        # Sections and findings go out VERBATIM, addresses and all: this is an
        # authenticated colonel surface and the full address is the answer
        # support needs (the CLI masks on its own side; that masking must NOT be
        # copied here). Verbatim is safe to JSON-encode because Diagnose scrubs
        # invalid UTF-8 out of its Result before returning it — datastore fields
        # are bytes, and JSON.generate raises on a bad one. That guard lives in
        # the op precisely so this adapter and the CLI cannot drift; do not
        # re-implement it here (see Diagnose#utf8_safe_deep).
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
