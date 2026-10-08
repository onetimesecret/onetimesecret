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
      TTL                  = 120
      # Real SAML responses — encrypted assertions and large attribute
      # statements included — are well under 100 KB of base64. Anything
      # bigger is not an assertion this SP could accept, only storage.
      MAX_RESPONSE_BYTES   = 128_000
      # Admission per fixed TTL bucket: the global cap is the deployment-wide
      # storage bound shared by every host; the source limit is the share one
      # privacy-masked client address may take of it. Operators size both
      # from the environment (see .limits); these are the defaults.
      DEFAULT_GLOBAL_LIMIT = 256
      DEFAULT_SOURCE_LIMIT = 64
      # Ceiling for either limit. The Lua script compares the counters as
      # doubles, so an astronomically large value would turn imprecise or
      # infinite and stop being a cap at all; well before that, a limit this
      # large is no longer a storage bound (1,000,000 x 128,000 bytes per bucket).
      MAX_LIMIT            = 1_000_000
      GLOBAL_LIMIT_VAR     = 'SAML_CALLBACK_GLOBAL_LIMIT'
      SOURCE_LIMIT_VAR     = 'SAML_CALLBACK_SOURCE_LIMIT'
      HANDLE_PATTERN       = /\A[0-9a-f]{64}\z/
      PREFIX               = 'saml:callback'

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
              TTL, global_limit, source_limit, Digest::SHA256.hexdigest(source.to_s), payload
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

      # @return [Integer] staged values admitted per bucket across all hosts
      def global_limit
        limits.fetch(:global)
      end

      # @return [Integer] staged values admitted per bucket per masked source
      def source_limit
        limits.fetch(:source)
      end

      # Forget the memoized environment read (specs).
      def reset_limits!
        @limits = nil
      end

      # Read once, on first use, the way Onetime::SsoProvider::Saml reads its
      # SAML_* variables — never per request. Positive integers up to
      # MAX_LIMIT only; the source share can never exceed the global cap; an
      # invalid value logs a warning and falls back to the default rather than
      # failing a callback.
      def limits
        @limits ||= begin
          global = positive_integer_setting(GLOBAL_LIMIT_VAR, DEFAULT_GLOBAL_LIMIT)
          source = positive_integer_setting(SOURCE_LIMIT_VAR, DEFAULT_SOURCE_LIMIT)
          if source > global
            OT.lw "[saml_callback_store] #{SOURCE_LIMIT_VAR}=#{source} exceeds #{GLOBAL_LIMIT_VAR}=#{global}; using #{global}"
            source = global
          end
          { global: global, source: source }.freeze
        end
      end
      private :limits

      def positive_integer_setting(name, default)
        raw = ENV.fetch(name, '').to_s.strip
        return default if raw.empty?
        return raw.to_i if /\A[1-9]\d*\z/.match?(raw) && raw.to_i <= MAX_LIMIT

        OT.lw "[saml_callback_store] #{name}=#{raw[0, 32].inspect} is not a positive integer up to #{MAX_LIMIT}; using #{default}"
        default
      end
      private :positive_integer_setting

      # Include the resolved public host as well as the inbound Rack authority.
      # Keep the latter stable across PublicHostRewrite setting changes without
      # accepting alternate scopes. Multiple tenants can share an origin; the
      # public-host fields and normal tenant/setup/ACS gates still apply.
      def scope(env)
        if env.key?('onetime.original_http_host')
          original_host = env['onetime.original_http_host']
          # PublicHostRewrite also overwrites SERVER_NAME, so an absent Host
          # cannot be reconstructed safely from the remaining server fields.
          raise ArgumentError, 'Original SAML callback authority unavailable' if original_host.nil?

          env = env.merge('HTTP_HOST' => original_host)
        end
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
