# lib/onetime/operations/sessions/delete_session.rb
#
# frozen_string_literal: true

require 'onetime/operations/sessions/store'
require 'onetime/session/sidecar'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

module Onetime
  module Operations
    module Sessions
      # Delete (revoke / terminate) a single session — the SINGLE, audited
      # implementation of the session-delete verb (epic #40 / D3 / CONTRACT 4).
      #
      # This is the one mutating session verb. The colonel endpoint
      # (`DELETE /api/colonel/sessions/:session_id`) and the `bin/ots session delete`
      # CLI are thin adapters over it. The model mutation is IDENTICAL to the prior
      # inline CLI call (`dbclient.del(session_key)`); the op adds exactly one thing
      # the inline call lacked: one {Onetime::ColonelAuditEvent} per successful delete.
      #
      # Deleting a session logs that user out mid-flight, so the HTTP path gates it
      # behind AdminConfirmDialog typed-confirmation and the CLI behind a y/N prompt
      # (both in the adapter); the op itself just performs + audits.
      #
      # Stateless, single `#call`, returns an immutable {Result}. A delete of an id
      # with no live session key returns `status: :not_found` and records NO audit
      # event (nothing mutated) — the "only audit an actual change" rule.
      class Delete
        include Onetime::AuditedFailure

        # Audit verb recorded for every successful revoke.
        AUDIT_VERB = 'session.delete'

        # Destructive verb: record the attempt when the delete raises (the
        # success-path record below is unreachable in that case) and re-raise.
        audit_failures :call, verb: AUDIT_VERB, target: -> { @session_id }

        # @!attribute status [r] Symbol :deleted (removed) or :not_found (no-op)
        Result = Data.define(:status, :session_id, :key)

        # @param session_id [String] the bare session id to revoke.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        # @param dbclient [Object, nil] Redis-like client; defaults to Familia.dbclient.
        def initialize(session_id:, actor:, dbclient: nil)
          @session_id = session_id
          @actor      = actor
          @dbclient   = dbclient
        end

        # @return [Result]
        def call
          db  = @dbclient || Familia.dbclient
          key = Store.find_key(db, @session_id)

          unless key
            return Result.new(status: :not_found, session_id: @session_id, key: nil)
          end

          # Same mutation the CLI performed inline, preserved verbatim.
          db.del(key)

          # The sid's per-value sidecar keys (Onetime::SessionSidecar) go with
          # the blob — an exact O(registry) DEL by name, format-gated inside
          # purge so legacy non-hex ids no-op harmlessly. Derive the bare sid
          # from the resolved key: `key` may be a full `session:<sid>` shape
          # (find_key resolves several), which would fail purge's sid guard.
          Onetime::SessionSidecar.purge(Store.extract_id(key), dbclient: db)

          # One audit event per successful mutation. The session id is a public
          # identifier; never put session contents (tokens, etc.) into detail.
          #
          # FAIL-CLOSED (#4333): the blob and its sidecars are already deleted,
          # so nothing else survives to say the session was killed or by whom.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @session_id,
            result: :success,
            fail_closed: true,
          )

          Result.new(status: :deleted, session_id: @session_id, key: key)
        end
      end
    end
  end
end
