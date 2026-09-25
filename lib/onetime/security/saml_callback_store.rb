# frozen_string_literal: true

require 'digest'
require 'json'
require 'securerandom'

module Onetime
  module Security
    # Untrusted transport data, never an authentication result. GET reads are
    # non-destructive; only the strategy, after validating the signed transaction,
    # may atomically consume the exact value it read.
    module SamlCallbackStore
      TTL                = 120
      MAX_RESPONSE_BYTES = 350_000
      GLOBAL_LIMIT       = 256
      SOURCE_LIMIT       = 20
      HANDLE_PATTERN     = /\A[0-9a-f]{64}\z/
      PREFIX             = 'saml:callback'

      class CapacityExceeded < StandardError; end

      STAGE = <<~LUA
        local count = tonumber(redis.call('HGET', KEYS[1], 'total') or '0')
        local source = tonumber(redis.call('HGET', KEYS[1], ARGV[4]) or '0')
        if count >= tonumber(ARGV[2]) or source >= tonumber(ARGV[3]) then return 0 end
        if not redis.call('SET', KEYS[2], ARGV[5], 'NX', 'EX', ARGV[1]) then return 0 end
        redis.call('HINCRBY', KEYS[1], 'total', 1)
        redis.call('HINCRBY', KEYS[1], ARGV[4], 1)
        if count == 0 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
        return 1
      LUA

      CONSUME = <<~LUA
        if redis.call('GET', KEYS[1]) ~= ARGV[1] then return 0 end
        return redis.call('DEL', KEYS[1])
      LUA

      extend self

      def stage(response:, scope:, source:, dbclient: Familia.dbclient, now: Time.now)
        raise ArgumentError, 'Invalid SAML response size' unless response.is_a?(String) && response.bytesize.between?(1, MAX_RESPONSE_BYTES)

        handle  = SecureRandom.hex(32)
        payload = JSON.generate('response' => response, 'scope' => scope)
        # A single bounded hash per time bucket: even a flood of distinct
        # source addresses cannot create an unbounded rate-limiter keyspace.
        # Only successful admissions spend quota. Counting source-rejected
        # requests globally would let one source deny every other source.
        bucket  = "#{PREFIX}:rate:#{now.to_i / TTL}"
        result  = without_datastore_capture do
          dbclient.eval(
            STAGE,
            keys: [bucket, key(handle)],
            argv: [
              TTL, GLOBAL_LIMIT, SOURCE_LIMIT, Digest::SHA256.hexdigest(source.to_s), payload
            ],
          )
        end
        raise CapacityExceeded, 'SAML callback staging capacity exceeded' unless result == 1

        handle
      end

      def read(handle, scope:, dbclient: Familia.dbclient)
        return unless handle.is_a?(String) && HANDLE_PATTERN.match?(handle)

        raw = without_datastore_capture { dbclient.get(key(handle)) }
        return unless raw.is_a?(String)

        data = JSON.parse(raw)
        return unless data['scope'] == scope && data['response'].is_a?(String) && data['response'].bytesize.between?(1, MAX_RESPONSE_BYTES)

        [data['response'], raw]
      end

      def consume(handle, raw, dbclient: Familia.dbclient)
        return false unless handle.is_a?(String) && HANDLE_PATTERN.match?(handle)

        without_datastore_capture { dbclient.eval(CONSUME, keys: [key(handle)], argv: [raw]) } == 1
      end

      # Include the resolved public host as well as the Rack authority. Behind
      # a rewriting proxy multiple tenants can share the latter. No input here
      # authorizes a host; the normal tenant/setup/ACS gates still run on GET.
      def scope(env)
        req      = Rack::Request.new(env)
        detected = defined?(Rack::DetectHost) ? env[Rack::DetectHost.result_field_name] : nil
        [req.base_url, env['onetime.display_domain'].to_s, detected.to_s, req.path]
      end

      # Redis instrumentation includes keys even without PII, and Lua arguments
      # with PII enabled. A copied scope drops only these calls' spans and
      # breadcrumbs, without changing SDK configuration for concurrent requests.
      def without_datastore_capture
        return yield unless defined?(Sentry) && Sentry.initialized?

        Sentry.with_scope do |scope|
          scope.clear
          yield
        end
      end
      private :without_datastore_capture

      def key(handle)
        "#{PREFIX}:#{handle}"
      end
    end
  end
end
