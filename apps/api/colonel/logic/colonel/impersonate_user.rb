# apps/api/colonel/logic/colonel/impersonate_user.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'
require 'auth/operations/customers/impersonate'

module ColonelAPI
  module Logic
    module Colonel
      # Start impersonating a customer in the CURRENT colonel session.
      #
      # POST /api/colonel/users/:user_id/impersonate
      # Body: { "reason": "..." }
      #
      # Thin adapter over {Auth::Operations::Customers::Impersonate} — the
      # single implementation. The OP writes the session marker and owns the
      # ColonelAuditEvent; this class NEVER audits, which would double-record.
      #
      # ## This is the last request this session can make to /api/colonel
      #
      # The op writes the overlay onto `sess`, and from the NEXT request on
      # BaseSessionAuthStrategy resolves the TARGET as the authenticated user
      # (Onetime::SessionImpersonation.resolve). So the role check that lets
      # this endpoint run will fail on every subsequent colonel call, and
      # Middleware::ImpersonationContext blocks `/api/colonel/*` outright. The
      # response therefore carries the `redirect` the console must follow — a
      # HARD navigation out of the admin bundle, not a router push.
      #
      # ## Reason is mandatory
      #
      # Not for the UI's benefit: the audit event is the durable record of WHY
      # an operator read a customer's account, and a nullable reason makes that
      # record worthless. The op refuses a blank reason as a backstop; this
      # rejects it as a 422 with a field so the dialog can point at it.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ImpersonateUser < ColonelAPI::Logic::Base
        include AccountIdentifier

        # Long enough for a ticket reference plus a sentence; bounded so the
        # audit detail stays small (ColonelAuditEvent truncates at 256 per
        # value anyway, but a rejected 10KB reason is better than a silently
        # truncated one).
        MAX_REASON_LENGTH = 500

        # Op-raised refusals that map to a 422 form error rather than a 500.
        OP_REFUSALS = [
          Auth::Operations::Customers::Impersonate::AlreadyImpersonating,
          Auth::Operations::Customers::Impersonate::AnonymousTarget,
          Auth::Operations::Customers::Impersonate::MissingReason,
          Auth::Operations::Customers::Impersonate::PrivilegedTarget,
          Auth::Operations::Customers::Impersonate::SuspendedTarget,
        ].freeze

        attr_reader :user_id, :reason, :user, :result

        def process_params
          # sanitize_account_identifier (NOT sanitize_identifier): operators
          # paste emails, and the plain sanitizer strips '@' and '.'.
          @user_id = sanitize_account_identifier(params['user_id'])
          @reason  = sanitize_plain_text(params['reason'], max_length: MAX_REASON_LENGTH).to_s.strip
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
          raise_form_error('A reason is required to impersonate', field: :reason) if reason.empty?

          @user = resolve_account(user_id)
          raise_not_found('User not found') unless user&.exists?

          # UX-level guards; the op enforces every one of them again as a
          # backstop, so an adapter that forgot one cannot start a bad session.
          raise_form_error('Cannot impersonate an anonymous user', field: :user_id) if user.anonymous?
          raise_form_error('Cannot impersonate a colonel account', field: :user_id) if user.role?('colonel')
          raise_form_error('Cannot impersonate a suspended account', field: :user_id) if user.suspended?
        end

        def process
          # actor is the acting colonel's PUBLIC id (extid), never an objid.
          # `cust` is still the colonel here: the overlay does not exist yet.
          @result = Auth::Operations::Customers::Impersonate.new(
            customer: user,
            actor: cust.extid,
            reason: reason,
            session: sess,
          ).call

          success_data
        rescue *OP_REFUSALS => ex
          # Every one of these is a precondition the op re-checked as a
          # backstop after raise_concerns already rejected it. Reaching one
          # here means the two disagreed (a TOCTOU race — the target was
          # promoted or suspended between the check and the call), which is a
          # 422 with the op's own message, not a 500.
          raise_form_error(ex.message, field: :user_id)
        end

        def success_data
          {
            record: {
              impersonation_id: result.impersonation_id,
              target_extid: user.extid,
              target_email: user.email,
              expires_at: result.expires_at,
              # Where the console sends the browser. The customer surface, not
              # a console route: /colonel is blocked for the duration.
              redirect: '/',
            },
            details: {},
          }
        end
      end
    end
  end
end
