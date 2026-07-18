# lib/onetime/operations/ratelimit/inspect.rb
#
# frozen_string_literal: true

require 'onetime/operations/ratelimit/registry'

module Onetime
  module Operations
    module RateLimit
      # Inspect the current Redis state of a rate limiter for one subject — the
      # SINGLE implementation of the limiter-inspect verb (ticket #44). The colonel
      # endpoint (`GET /api/colonel/ratelimit/inspect`) is a thin adapter; the
      # `bin/ots ratelimit keys` CLI serves the SAME capability by emitting the
      # `TTL`/`GET` commands for the SAME {Registry}-derived keys (it deliberately
      # never touches Redis itself — see ratelimit_command.rb).
      #
      # READ-ONLY: reads TTL + value for each key, mutates nothing, records NO
      # AdminAuditEvent (CONTRACT 4). Bounded to the fixed keys the registry
      # names PLUS, for two-tier limiters, a subject-scoped SCAN of the per-IP
      # tier's variable-suffix keys (RL-1). The SCAN is bounded to one subject
      # (a locked tier stops accruing new IPs) and cursor-based — never a
      # blocking KEYS, and never an unscoped walk (CONTRACT 6).
      class Inspect
        # State of one backing key.
        # @!attribute ttl [r] seconds remaining, or nil for no-expiry / absent.
        # @!attribute exists [r] whether the key is currently set.
        Entry = Data.define(:key, :ttl, :value, :exists)

        Result = Data.define(:kind, :subject, :entries)

        # @param kind [String] a known limiter kind (see {Registry}).
        # @param subject [String] the IP / identifier the limiter keys on.
        def initialize(kind:, subject:)
          @kind    = kind.to_s
          @subject = subject.to_s
        end

        # @return [Result]
        # @raise [ArgumentError] when the kind is unknown.
        def call
          exact_keys = Registry.keys_for(@kind, @subject)
          raise ArgumentError, "Unknown rate limiter: #{@kind.inspect}" unless exact_keys

          db = Registry.dbclient_for(@kind)

          # Fold in the two-tier per-IP keys (variable {ip} suffix) so an
          # operator can SEE a per-IP lockout before resetting it (RL-1).
          scanned = Registry.scan_patterns_for(@kind, @subject).flat_map { |pattern| scan_matches(db, pattern) }
          keys    = (exact_keys + scanned).uniq

          entries = keys.map do |key|
            raw_ttl = db.ttl(key)
            value   = db.get(key)

            Entry.new(
              key: key,
              # Collapse Redis's -1 (no expiry) / -2 (no key) sentinels to nil so
              # the wire shape is "seconds remaining, or null".
              ttl: raw_ttl.negative? ? nil : raw_ttl,
              value: value,
              exists: !value.nil?,
            )
          end

          Result.new(kind: @kind, subject: @subject, entries: entries)
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
