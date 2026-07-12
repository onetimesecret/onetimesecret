# lib/onetime/operations/sessions/delete_session.rb
#
# frozen_string_literal: true

require 'onetime/operations/sessions/store'
require 'onetime/models/admin_audit_event'

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
      # the inline call lacked: one {Onetime::AdminAuditEvent} per successful delete,
      # mirroring the Slice-4 {Onetime::Operations::BanIP} / `UnbanIP` precedent.
      #
      # Deleting a session logs that user out mid-flight, so the HTTP path gates it
      # behind AdminConfirmDialog typed-confirmation and the CLI behind a y/N prompt
      # (both in the adapter); the op itself just performs + audits.
      #
      # Stateless, single `#call`, returns an immutable {Result}. A delete of an id
      # with no live session key returns `status: :not_found` and records NO audit
      # event (nothing mutated) — the "only audit an actual change" rule.
      class Delete
        # Audit verb recorded for every successful revoke.
        AUDIT_VERB = 'session.delete'

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

          # One audit event per successful mutation. The session id is a public
          # identifier; never put session contents (tokens, etc.) into detail.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @session_id,
            result: :success,
          )

          Result.new(status: :deleted, session_id: @session_id, key: key)
        end
      end
    end
  end
end
