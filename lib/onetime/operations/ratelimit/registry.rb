# lib/onetime/operations/ratelimit/registry.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation support — see decision D3. The security
# rate limiters (lib/onetime/security/*_rate_limiter.rb) are site-wide perimeter
# infrastructure with no single domain owner, so their admin inspect/reset verbs
# live in the central operations home alongside {Onetime::Operations::BanIP}.
#
# This file defines ONLY a frozen registry constant + pure key-derivation
# helpers. It references NO models or Redis at load time — the per-limiter
# database is resolved lazily through a proc — so the delay-boot `bin/ots
# ratelimit` CLI can require it without booting the application.

module Onetime
  module Operations
    module RateLimit
      # SINGLE source of truth mapping each rate-limiter kind to its subject type,
      # its Redis key templates, and the client that holds those keys. The
      # `bin/ots ratelimit keys` CLI aliases its own `LIMITERS` to this so the
      # emitted valkey-cli commands stay byte-identical, and the Inspect/Reset ops
      # derive their keys from the SAME templates — write the key shape once.
      #
      # `keys` are `format`-style templates: `%s` is filled with the subject. This
      # is the golden-master contract the CLI emits; do not reshape it.
      #
      # `scan_keys` (optional) are `format`-style SCAN MATCH templates for tiers
      # whose keys carry a VARIABLE suffix — e.g. the per-IP lockouts written by
      # the two-tier passphrase / login limiters (`...:{subject}:{ip}`). The
      # exact `keys` above cannot name them (the {ip} is unknown), so the
      # Inspect/Reset ops expand these patterns and SCAN for matches (RL-1). The
      # static-key `bin/ots ratelimit keys` CLI ignores `scan_keys` — it only
      # emits commands for concrete keys. Keep these templates byte-identical
      # with the private `*_key` methods in the matching security module.
      #
      # `dbclient` is a proc (evaluated at call time, never at require) returning
      # the Redis/Valkey client whose shard holds the limiter's keys — matching the
      # `redis` accessor inside each `lib/onetime/security/*_rate_limiter.rb`.
      module Registry
        LIMITERS = {
          'feedback' => {
            subject: 'IP address',
            keys: ['feedback:submissions:%s', 'feedback:locked:%s'],
            dbclient: -> { Onetime::Feedback.dbclient },
          },
          'passphrase' => {
            subject: 'secret identifier',
            keys: ['passphrase:attempts:%s', 'passphrase:locked:%s'],
            scan_keys: ['passphrase:attempts:%s:*', 'passphrase:locked:%s:*'],
            dbclient: -> { Onetime::Secret.dbclient },
          },
          'invite' => {
            subject: 'IP address',
            keys: ['invite_attempts:%s', 'invite_locked:%s'],
            dbclient: -> { Onetime::Secret.dbclient },
          },
          'login' => {
            subject: 'email',
            keys: ['login:attempts:%s', 'login:locked:%s'],
            scan_keys: ['login:attempts:%s:*', 'login:locked:%s:*'],
            dbclient: -> { Onetime::Customer.dbclient },
          },
          'dns' => {
            subject: 'domain identifier (sanitized)',
            keys: ['dns:ratelimit:%s'],
            dbclient: -> { Onetime::CustomDomain.dbclient },
          },
        }.freeze

        # Redis glob metacharacters escaped when a subject is interpolated into a
        # SCAN MATCH pattern, so a subject like an email can never widen the
        # match (only the trailing template `*` stays a wildcard).
        SCAN_GLOB_METACHARS = /[\\*?\[\]]/

        module_function

        # @return [Array<String>] the known limiter kinds, in registry order.
        def kinds
          LIMITERS.keys
        end

        # @param kind [String]
        # @return [Hash, nil] the limiter metadata, or nil for an unknown kind.
        def fetch(kind)
          LIMITERS[kind.to_s]
        end

        # @return [Boolean] whether the kind is a known limiter.
        def known?(kind)
          LIMITERS.key?(kind.to_s)
        end

        # Derive the concrete Redis keys for a kind + subject. This is the one
        # place the templates are expanded — the CLI, Inspect, and Reset all call
        # through here so the keys can never drift.
        #
        # @param kind [String]
        # @param subject [String]
        # @return [Array<String>, nil] concrete keys, or nil for an unknown kind.
        def keys_for(kind, subject)
          meta = fetch(kind)
          return nil unless meta

          meta[:keys].map { |tmpl| format(tmpl, subject) }
        end

        # Derive the concrete SCAN MATCH patterns for a kind's variable-suffix
        # tiers (per-IP lockouts), or [] when the kind has none. The subject is
        # glob-escaped first so only the trailing template wildcard matches
        # freely. The Inspect/Reset ops SCAN these to reach keys the exact
        # {keys_for} set cannot name (RL-1).
        #
        # @param kind [String]
        # @param subject [String]
        # @return [Array<String>, nil] concrete patterns, or nil for an unknown kind.
        def scan_patterns_for(kind, subject)
          meta = fetch(kind)
          return nil unless meta

          escaped = subject.to_s.gsub(SCAN_GLOB_METACHARS) { |c| "\\#{c}" }
          Array(meta[:scan_keys]).map { |tmpl| format(tmpl, escaped) }
        end

        # Resolve the Redis/Valkey client holding a kind's keys (call-time).
        #
        # @param kind [String]
        # @return [Object, nil] the dbclient, or nil for an unknown kind.
        def dbclient_for(kind)
          meta = fetch(kind)
          return nil unless meta

          meta[:dbclient].call
        end
      end
    end
  end
end
