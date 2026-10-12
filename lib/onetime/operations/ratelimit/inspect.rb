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
      # ColonelAuditEvent (CONTRACT 4). Bounded to the fixed keys the registry
      # names PLUS, for two-tier limiters, a subject-scoped SCAN of the per-IP
      # tier's variable-suffix keys (RL-1). The SCAN is bounded to one subject
      # (a locked tier stops accruing new IPs) and cursor-based — never a
      # blocking KEYS, and never an unscoped walk (CONTRACT 6).
      class Inspect
        # State of one backing key.
        # @!attribute ttl [r] seconds remaining, or nil for no-expiry / absent.
        # @!attribute exists [r] whether the key is currently set.
        Entry = Data.define(:key, :ttl, :value, :exists)

        # @!attribute scan_complete [r] false when the per-IP SCAN stopped at
        #   the caller's deadline, so `entries` may be missing per-IP keys.
        #   Always true when no deadline was given.
        Result = Data.define(:kind, :subject, :entries, :scan_complete) do
          def initialize(kind:, subject:, entries:, scan_complete: true)
            super
          end
        end

        # @param kind [String] a known limiter kind (see {Registry}).
        # @param subject [String] the IP / identifier the limiter keys on.
        # @param scan_deadline [Numeric, nil] wall-clock budget in seconds for
        #   the per-IP SCANs, shared across patterns. nil walks to completion
        #   (the CLI and the explicit inspect endpoint). A caller that renders
        #   inside a page request passes one, because the walk is
        #   O(keyspace) and a large shared database can outlast the proxy's
        #   upstream timeout. The exact keys are always read in full.
        def initialize(kind:, subject:, scan_deadline: nil)
          @kind          = kind.to_s
          @subject       = subject.to_s
          @scan_deadline = scan_deadline
        end

        # @return [Result]
        # @raise [ArgumentError] when the kind is unknown.
        def call
          exact_keys = Registry.keys_for(@kind, @subject)
          raise ArgumentError, "Unknown rate limiter: #{@kind.inspect}" unless exact_keys

          db = Registry.dbclient_for(@kind)

          # Fold in the two-tier per-IP keys (variable {ip} suffix) so an
          # operator can SEE a per-IP lockout before resetting it (RL-1).
          deadline = @scan_deadline && (monotonic_now + @scan_deadline)
          scans    = Registry.scan_patterns_for(@kind, @subject).map { |pattern| scan_matches(db, pattern, deadline) }
          scanned  = scans.flat_map(&:first)
          complete = scans.all?(&:last)
          keys     = (exact_keys + scanned).uniq

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

          Result.new(kind: @kind, subject: @subject, entries: entries, scan_complete: complete)
        end

        private

        # Cursor-scan (non-blocking, unlike KEYS) for the concrete keys matching
        # a registry SCAN pattern. Scoped to one subject's variable-suffix tier,
        # so the returned set is bounded even though SCAN walks the keyspace.
        #
        # @param deadline [Float, nil] monotonic time to stop at; nil walks to
        #   the end of the keyspace. At least one SCAN call always runs.
        # @return [Array(Array<String>, Boolean)] the matches, and whether the
        #   walk reached the end of the keyspace.
        def scan_matches(db, pattern, deadline)
          found  = []
          cursor = '0'
          loop do
            cursor, batch = db.scan(cursor, match: pattern, count: Registry::SCAN_COUNT)
            found.concat(batch)
            return [found, true] if cursor == '0'
            return [found, false] if deadline && monotonic_now >= deadline
          end
        end

        # Monotonic clock: a wall-clock deadline must not move with NTP steps.
        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
