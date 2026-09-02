# lib/onetime/operations/sessions/revoke_for_customer.rb
#
# frozen_string_literal: true

require 'onetime/operations/sessions/store'
require 'onetime/session/sidecar'
require 'onetime/models/session_metadata'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/audit_reason'

module Onetime
  module Operations
    module Sessions
      # Revoke one of a customer's sessions from the colonel per-customer view —
      # the mutating half of the per-customer session feature (spec
      # docs/specs/colonel-ui/40-*).
      #
      # ## What actually logs the user out (adaptation #1)
      #
      # In this codebase a session dies by deleting the encrypted `session:<sid>`
      # blob, NOT by removing a Rodauth active_session_keys row (that table only
      # gates Rodauth-mounted routes, mode=full — not the general blob-validated
      # request path). So we invalidate by deleting the live key, reusing the
      # SAME primitive the global {Delete} op uses ({Store.find_key} → `del`).
      #
      # This op deliberately does NOT delegate to {Delete}: that op writes its own
      # audit event (`verb: 'session.delete'`, `target: <session_id>`). Composing
      # it here would double-audit with a different target. We reuse only Store —
      # the key logic — and write exactly ONE customer-scoped audit event.
      #
      # ## Idempotent tidy
      #
      # After invalidation (whether or not a live blob existed) it destroys the
      # sidecar and ZREMs the sid from Customer#active_sessions, then records one
      # {Onetime::ColonelAuditEvent}. Revoking an already-gone session still tidies
      # the index + returns cleanly (`revoked: true`) — the colonel took an
      # intentional action and the index prune is a real mutation; `detail`
      # carries whether a live blob was present.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class RevokeForCustomer
        include Onetime::AuditedFailure
        include Onetime::AuditReason

        # Audit verb recorded for every customer-scoped session revoke.
        AUDIT_VERB = 'session.revoke'

        # Takeover-mitigation verb: a revoke that raises leaves the operator
        # unsure whether the session survived, so the attempt is recorded
        # (`result: :failure`) and the error re-raised unchanged. Composition is
        # not a concern here — this op deliberately does not delegate to
        # {Delete} (see above), so only one audited frame can fire.
        audit_failures :call, verb: AUDIT_VERB, target: -> { @custid }

        # @!attribute revoked [r] Boolean always true on a completed call (idempotent)
        # @!attribute blob_deleted [r] Boolean whether a live session blob existed + was deleted
        Result = Data.define(:session_id, :revoked, :blob_deleted)

        # @param custid [String] the target customer (route param; extid/email/objid).
        # @param session_id [String] the bare session id to revoke.
        # @param actor [String, #extid] acting colonel's PUBLIC identity (extid).
        # @param reason [String, nil] OPTIONAL operator-supplied why (#4338),
        #   recorded in the audit detail. Blank is treated as absent and the
        #   detail keeps its pre-#4338 shape. See {Onetime::AuditReason} for
        #   the bound and the optional-now / required-later rollout.
        # @param dbclient [Object, nil] Redis-like client; defaults to Familia.dbclient.
        def initialize(custid:, session_id:, actor:, reason: nil, dbclient: nil)
          @custid      = custid
          @session_id  = session_id
          @actor       = actor
          @reason      = normalize_reason(reason)
          @dbclient    = dbclient
        end

        # @return [Result]
        def call
          db  = @dbclient || Familia.dbclient
          key = Store.find_key(db, @session_id)

          # Invalidate: delete the live encrypted blob. This is the actual logout.
          blob_deleted = false
          if key
            db.del(key)
            blob_deleted = true
          end

          # Per-value sidecar keys are purged UNCONDITIONALLY (idempotent,
          # exact registry-derived names) — an operator revoking a sid wants
          # ALL of its state gone, even when the blob itself had already
          # expired or been deleted out from under the sidecars. purge is gated
          # on the bare-hex sid format, so extract it from the resolved key (or
          # the raw input when no live blob existed) — a full `session:<sid>`
          # would otherwise fail the guard and leave the sidecars orphaned.
          Onetime::SessionSidecar.purge(Store.extract_id(key || @session_id), dbclient: db)

          # Tidy the sidecar + the per-customer index (both idempotent). Capture the
          # sidecar's recorded owner BEFORE destroying it so a mismatch — the sid
          # belongs to a different customer than the route names — is auditable.
          meta            = Onetime::SessionMetadata.load(@session_id)
          session_user_id = meta&.user_id
          meta&.destroy!
          customer        = load_customer
          if customer
            customer.active_sessions&.remove(@session_id)
          else
            OT.ld("[RevokeForCustomer] no customer for #{@custid}; index prune skipped")
          end

          # One customer-scoped audit event per revoke. session_id is a public
          # identifier; never put session contents into detail.
          #
          # Ownership note: this is a colonel-only takeover-mitigation tool, so the
          # delete is NOT gated on the sidecar (best-effort, possibly stale) — an
          # operator pointing at a sid wants it gone. But when the sidecar records a
          # DIFFERENT owner than the route customer we surface `session_user_id` in
          # detail so the revoke is not silently mis-attributed. The true owner's
          # stale index member self-heals via ListForCustomer's blob-liveness prune.
          detail = with_reason(session_id: @session_id, blob_deleted: blob_deleted)
          if session_user_id && customer && session_user_id != customer.extid
            detail[:session_user_id] = session_user_id
          end
          # FAIL-CLOSED (#4333): the revoked session is deleted, not marked, so
          # the trail is the only evidence the operator did this.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @custid,
            result: :success,
            detail: detail,
            fail_closed: true,
          )

          Result.new(session_id: @session_id, revoked: true, blob_deleted: blob_deleted)
        end

        private

        # Same resolution as ListForCustomer / get_user_details: extid → email →
        # objid. nil is tolerated — the blob delete + sidecar destroy already ran,
        # so a missing customer only skips the (already-absent) index prune.
        def load_customer
          customer = Onetime::Customer.load_by_extid_or_email(@custid) ||
                     Onetime::Customer.load(@custid)
          return nil unless customer&.exists?

          customer
        end
      end
    end
  end
end
