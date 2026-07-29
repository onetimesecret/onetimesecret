# apps/api/account/logic/account/confirm_email_change.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/logic/sso_only_gating'
require 'auth/operations/customers/change_email'

module AccountAPI::Logic
  module Account
    using Familia::Refinements::TimeLiterals

    # POST /api/account/confirm-email-change (auth=noauth) — the redemption half
    # of the self-service email change.
    #
    # THIN ADAPTER (#3731 PR-C2). This class owns ONLY what an adapter owns:
    # token lookup, token validation, mapping the operation's status to the
    # HTTP-facing form error, and the current request's Rack session. The
    # cross-store mutation itself — Postgres `accounts.email`, the Familia
    # Customer hash, the global and org-scoped email indexes, the default
    # workspace's contact_email, the pending-change markers, session revocation
    # and the notifications — belongs to
    # {Auth::Operations::Customers::ChangeEmail}, which is also the ONLY thing
    # that records the audit event. Do not re-implement any of it here; the
    # colonel endpoint and `bin/ots customers change-email` call the same op and
    # must not be able to drift from this path.
    #
    # `require_verification: false` is deliberate and is the one parameter this
    # adapter differs from the operator adapters on (D34): the token the caller
    # just redeemed IS proof of ownership of the new address, so the account
    # keeps its verified status. An operator-initiated change has no such proof
    # and resets verification.
    class ConfirmEmailChange < AccountAPI::Logic::Base
      include Onetime::LoggerMethods
      include Onetime::Logic::SsoOnlyGating

      attr_reader :secret, :change_result

      def process_params
        @token  = params['token'].to_s.strip
        @secret = Onetime::Secret.find_by_identifier(@token) unless @token.empty?
      end

      def raise_concerns
        require_non_sso_only!

        raise OT::MissingSecret if @secret.nil?
        raise OT::MissingSecret unless @secret.exists?
        raise OT::MissingSecret if @secret.custid.to_s == 'anon'

        raise_form_error 'This link has expired', error_type: 'expired' unless @secret.verification?

        @owner = @secret.load_owner
        raise_form_error 'Invalid confirmation link', error_type: 'invalid' if @owner.nil?

        # Verify the pending_email_change matches
        unless Rack::Utils.secure_compare(@owner.pending_email_change.to_s, @secret.identifier)
          raise_form_error 'This confirmation link is no longer valid', error_type: 'invalid'
        end
      end

      def process
        # Read the ciphertext BEFORE delegating — the operation destroys the
        # pending verification Secret as part of clearing the pending markers.
        new_email = sanitize_email(@secret.decrypted_secret_value)

        if new_email.empty?
          raise_form_error 'Unable to determine new email address', error_type: 'system_error'
        end

        OT.info "[confirm-email-change] Confirming email change cid/#{@owner.objid} " \
                "old/#{OT::Utils.obscure_email(@owner.email)} new/#{OT::Utils.obscure_email(new_email)}"

        @change_result = Auth::Operations::Customers::ChangeEmail.new(
          customer: @owner,
          # The acting principal is the account holder themselves — a REAL,
          # public identity (ADR-023), never a synthesized customer and never an
          # internal objid. `cust` is nil here: this is a noauth route.
          actor: @owner.extid,
          new_email: new_email,
          dry_run: false,
          require_verification: false, # D34 — the token already proved ownership
          revoke_sessions: true,
          notify: true,
        ).call

        # ADAPTER-OWNED, by construction: the operation deletes every STORED
        # session blob, but the current request's in-memory Rack session is
        # written back by the session middleware after this call returns — which
        # would re-create the blob that was just revoked. The op has no request
        # context, so this cannot move into it.
        #
        # Runs BEFORE the status mapping: a `:partial` whose swap LANDED
        # (`:secondary_writes_incomplete` — both authoritative stores hold the new
        # address) revokes sessions too, and the mapping below raises on
        # `:partial`. Clearing only on the paths that return would leave the one
        # session blob the revocation exists to kill alive on exactly the messy
        # path.
        clear_current_session(@change_result)

        handle_result_status(@change_result)

        OT.info "[confirm-email-change] Email change confirmed cid/#{@owner.objid} " \
                "status/#{@change_result.status} new/#{OT::Utils.obscure_email(new_email)} " \
                "warnings/#{@change_result.warnings.inspect}"

        success_data
      end

      def success_data
        { confirmed: true, redirect: '/signin' }
      end

      private

      # Drop the current request's session, but ONLY once the address has
      # actually changed hands — on `:email_taken` and the system-error statuses
      # nothing moved and signing the caller out would be gratuitous.
      def clear_current_session(result)
        return unless sess
        return unless swap_landed?(result)

        sess.clear
      end

      # `:no_change` counts: the account already holds the address, the
      # redemption is idempotent, and this surface still sends the caller to
      # /signin. `:verification_not_reset` counts: the op only computes it AFTER
      # the swap landed and RevokeAllForCustomer ran — unreachable here today
      # (this adapter passes `require_verification: false`), but if that
      # parameter ever changes, skipping the clear would write this session back
      # and resurrect the blob the op just deleted. `:partial` counts only in
      # the sub-case where the Customer hash committed — the other sub-case
      # rolled the accounts row back.
      def swap_landed?(result)
        return true if [:success, :no_change, :verification_not_reset].include?(result.status)

        result.status == :partial && result.warnings.include?(:secondary_writes_incomplete)
      end

      # Map the operation's status vocabulary onto this surface's form errors.
      # Messages and error_types are preserved verbatim from the pre-extraction
      # implementation so the frontend's error handling is unaffected.
      def handle_result_status(result)
        case result.status
        # :no_change means the address already equals the current one — the
        # redemption is idempotent rather than an error.
        when :success, :no_change
          nil

        # Claimed by another account between the request and this redemption.
        when :email_taken
          raise_form_error 'This email is no longer available', error_type: 'unavailable'

        # RequestEmailChange validated the address before minting the token, so
        # reaching either of these means the stored ciphertext is unusable.
        when :invalid_email, :not_found
          raise_form_error 'Unable to determine new email address', error_type: 'system_error'

        # :partial — SQL committed, the Redis side did not complete. The op has
        # already recorded the audit event and compensated where it safely
        # could; `customers doctor --check auth_email_drift` is the remediation.
        # Where the swap LANDED the op also revoked sessions and mailed both
        # addresses, and `clear_current_session` has already dropped this one —
        # so the caller is signed out even though this reports an error.
        #
        # `:verification_not_reset` cannot reach this branch: it is only produced
        # when `require_verification: true`, and this adapter always passes false
        # (D34 — the redeemed token is the proof of ownership). It falls into the
        # fail-closed `else` deliberately rather than being whitelisted above, so
        # if that parameter is ever changed the surface refuses instead of
        # reporting a clean success — but it IS a swap-landed status, so
        # `swap_landed?` counts it and the session clear has already fired.
        else
          auth_logger.error '[confirm-email-change] Email change did not fully land',
            extid: @owner.extid,
            status: result.status,
            warnings: result.warnings
          raise_form_error 'Email change could not be completed', error_type: 'system_error'
        end
      end
    end
  end
end
