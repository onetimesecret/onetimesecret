# lib/onetime/operations/ratelimit/reset.rb
#
# frozen_string_literal: true

require 'onetime/operations/ratelimit/registry'
require 'onetime/models/admin_audit_event'

module Onetime
  module Operations
    module RateLimit
      # Reset (clear) a rate limiter's Redis state for one subject — the SINGLE,
      # audited implementation of the limiter-reset verb (ticket #44 / CONTRACT 4).
      # The colonel endpoint (`POST /api/colonel/ratelimit/reset`) is a thin
      # adapter. The `bin/ots ratelimit keys` CLI serves the SAME capability by
      # emitting a `DEL` command over the SAME {Registry}-derived keys (it never
      # executes it — the operator does), which is why the CLI itself takes no
      # audit path.
      #
      # The DELETE is exactly the CLI's emitted `DEL <keys>` (and equivalent to the
      # limiter modules' own `clear_*_rate_limit!`). The op adds one thing: exactly
      # one {Onetime::AdminAuditEvent} per reset that ACTUALLY removed a key. A
      # reset of an already-clear subject is an idempotent no-op — `status:
      # :not_set`, NO audit event (the "only audit an actual change" rule shared
      # with UnbanIP / ClearBanner). Bounded to the registry's fixed key set
      # (CONTRACT 6).
      class Reset
        # Audit verb recorded for every reset that removed at least one key.
        AUDIT_VERB = 'ratelimit.reset'

        # @!attribute status [r] :success (something removed) or :not_set (no-op)
        Result = Data.define(:status, :kind, :subject, :keys, :deleted)

        # @param kind [String] a known limiter kind (see {Registry}).
        # @param subject [String] the IP / identifier the limiter keys on.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        def initialize(kind:, subject:, actor:)
          @kind    = kind.to_s
          @subject = subject.to_s
          @actor   = actor
        end

        # @return [Result]
        # @raise [ArgumentError] when the kind is unknown.
        def call
          exact_keys = Registry.keys_for(@kind, @subject)
          raise ArgumentError, "Unknown rate limiter: #{@kind.inspect}" unless exact_keys

          db = Registry.dbclient_for(@kind)

          # Two-tier limiters (passphrase, login) also write per-IP keys with a
          # variable {ip} suffix. The exact key set can't name them, so SCAN the
          # registry's patterns and fold the matches in — otherwise a
          # /24-collision-locked recipient stays locked with no operator remedy
          # (RL-1). Bounded per subject (a locked tier stops accruing new IPs).
          scanned = Registry.scan_patterns_for(@kind, @subject).flat_map { |pattern| scan_matches(db, pattern) }
          keys    = (exact_keys + scanned).uniq

          deleted = db.del(*keys).to_i

          # No key existed → nothing mutated → idempotent no-op, records no audit.
          if deleted.zero?
            return Result.new(status: :not_set, kind: @kind, subject: @subject, keys: keys, deleted: 0)
          end

          # One audit event per successful reset. The subject may be an IP or a
          # (public) secret identifier; it is the audit target. Never record the
          # counter VALUES — only the fact + shape of the reset.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: "#{@kind}:#{@subject}",
            result: :success,
            detail: { kind: @kind, keys: keys.length, deleted: deleted },
          )

          Result.new(status: :success, kind: @kind, subject: @subject, keys: keys, deleted: deleted)
        end

        private

        # Cursor-scan (non-blocking, unlike KEYS) for the concrete keys matching
        # a registry SCAN pattern. Scoped to one subject's variable-suffix tier,
        # so the returned set is bounded even though SCAN walks the keyspace.
        def scan_matches(db, pattern)
          found  = []
          cursor = '0'
          loop do
            cursor, batch = db.scan(cursor, match: pattern, count: 100)
            found.concat(batch)
            break if cursor == '0'
          end
          found
        end
      end
    end
  end
end
