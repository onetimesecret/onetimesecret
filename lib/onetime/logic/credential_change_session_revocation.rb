# lib/onetime/logic/credential_change_session_revocation.rb
#
# frozen_string_literal: true

require 'onetime/jobs/publisher'
require 'onetime/operations/sessions/revoke_all_for_customer_except_current'

module Onetime
  module Logic
    # Simple-mode counterpart of the Rodauth after_change_password /
    # after_reset_password session-revocation hooks (security finding M-2:
    # sessions must not survive a password change/reset).
    #
    # Full (Rodauth) mode enforces M-2 from apps/web/auth/config/hooks/account.rb.
    # Those hooks never fire in simple mode — the application default
    # (lib/onetime/auth_config.rb) — so the simple-mode logic classes
    # (UpdatePassword, ResetPassword) run this mixin instead. Same three steps,
    # same ordering, same fail-secure posture as the hooks:
    #
    #   1. Stamp Customer#last_password_update — the credential watermark. The
    #      watermark, not the blob deletion below (hygiene), is the authoritative
    #      revocation boundary: session validation
    #      (AuthStrategies::Helpers#session_predates_credential_change?) rejects
    #      any blob authenticated at-or-before it on its very next request, so a
    #      blob the deletions never reach still dies there.
    #   2. Enqueue the async FULL sweep (#3810), untracked keyspace scan
    #      included. The publisher degrades to an inline sweep when jobs are
    #      disabled, so the sweep still happens without RabbitMQ. Enqueued
    #      BEFORE the inline revoke so it survives an inline-revoke raise — it
    #      is the durable retry.
    #   3. Inline tracked-only revoke. scan_untracked: false keeps the bounded
    #      keyspace SCAN + per-blob decrypt off the request path (mirroring the
    #      full-mode hooks, which keep it out of Rodauth's open SQL
    #      transaction); the guaranteed tracked kill still revokes every
    #      post-sidecar session immediately.
    #
    # Each step rescues independently and LOUDLY (error-level auth log + Sentry
    # when available): a failure in one must not mask the others, and none may
    # fail the credential change itself. Deliberately NOT
    # ErrorHandler.safe_execute — that helper swallows a raise into routine
    # :warn logging, so a non-revoking change would report success silently:
    # fail-OPEN for exactly the scenario M-2 defends against.
    #
    # Host classes must provide #auth_logger (Onetime::LoggerMethods).
    module CredentialChangeSessionRevocation
      private

      # Run the full M-2 sequence for +customer+.
      #
      # @param customer [Onetime::Customer] the account whose credential changed
      # @param except_session_id [String, nil] bare sid to PRESERVE (the session
      #   the user changed their password from). nil revokes ALL — the reset
      #   path, where the user followed an email link and holds no session
      #   worth keeping.
      # @return [Integer] the watermark stamped in step 1, or 0 when stamping
      #   failed. A caller keeping a session must re-stamp its authenticated_at
      #   STRICTLY past this value, or the auth-time `<=` check retires the
      #   kept session on its next request.
      def revoke_sessions_for_credential_change(customer, except_session_id: nil)
        watermark = stamp_credential_watermark(customer)
        enqueue_credential_change_sweep(customer, except_session_id)
        revoke_session_blobs_inline(customer, except_session_id)
        watermark
      end

      # Step 1: the credential watermark, via the same single-field fast-writer
      # Auth::Operations::UpdatePasswordMetadata uses in full mode.
      def stamp_credential_watermark(customer)
        watermark = Familia.now.to_i
        customer.last_password_update! watermark
        watermark
      rescue StandardError => ex
        report_credential_revocation_failure(
          :credential_watermark_stamp_FAILED, customer, ex,
          'credential watermark not stamped; the watermark is the authoritative ' \
          'revocation boundary — unreached pre-change blobs stay valid until TTL',
        )
        0
      end

      # Step 2: durable async full sweep (#3810). The worker honors the
      # credential watermark, so post-change sessions (including a kept,
      # re-stamped current session) are spared.
      def enqueue_credential_change_sweep(customer, except_session_id)
        Onetime::Jobs::Publisher.enqueue_session_revocation_sweep(
          customer.extid, except_session_id: except_session_id
        )
      rescue StandardError => ex
        report_credential_revocation_failure(
          :sessions_sweep_enqueue_FAILED, customer, ex,
          'async session sweep not enqueued; untracked pre-change blobs rely on ' \
          'watermark validation + TTL',
        )
      end

      # Step 3: immediate guaranteed kill of every OTHER tracked session blob —
      # the encrypted Redis blobs are the app's real auth gate
      # (BaseSessionAuthStrategy), so they must die now, not only when the
      # async sweep lands.
      #
      # `customer:` not `custid: customer.extid` — the op must act on the record
      # we hold, not on whatever the extid index resolves to (drift, #4205/#4217,
      # would silently zero-count the revoke and leave pre-change blobs live).
      def revoke_session_blobs_inline(customer, except_session_id)
        result = Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent.new(
          customer: customer,
          except_session_id: except_session_id,
          scan_untracked: false,
        ).call

        auth_logger.info '[credential-change] Revoked session blobs',
          customer_id: customer.extid,
          blobs_deleted: result.blobs_deleted,
          kept_current: !except_session_id.to_s.empty?
      rescue StandardError => ex
        report_credential_revocation_failure(
          :sessions_revoke_FAILED, customer, ex,
          'credential change succeeded but pre-change session blobs may still be live',
        )
      end

      # Loud, attributable failure path: distinct error-level event + Sentry
      # re-capture, so a non-revoking credential change alerts instead of
      # blending into routine logging.
      def report_credential_revocation_failure(event, customer, ex, security_warning)
        auth_logger.error "[credential-change] #{event}",
          customer_id: customer&.extid,
          logic: self.class.name,
          error: ex.message,
          security_warning: security_warning

        return unless defined?(Sentry) && Sentry.initialized?

        Sentry.capture_exception(ex) do |scope|
          scope.set_level(:error)
          scope.set_tags(component: 'auth.session_revocation', logic: self.class.name, finding: 'M-2')
          scope.set_context('session_revocation', { customer_id: customer&.extid })
        end
      end
    end
  end
end
