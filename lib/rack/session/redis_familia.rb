# lib/rack/session/redis_familia.rb

require 'rack/session/abstract/id'
require 'securerandom'
require 'json'

module Rack
  module Session
    class RedisFamilia < Abstract::PersistedSecure

      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge(
        expire_after: 86400,  # 24 hours
        key: 'ots.session',
        secure: true,
        httponly: true,
        same_site: :lax,
        redis_prefix: 'session'
      )

      def initialize(app, options = {})
        super(app, DEFAULT_OPTIONS.merge(options))
        @mutex = Mutex.new
        @redis_prefix = @default_options[:redis_prefix]
      end

      def generate_sid(*)
        SecureRandom.urlsafe_base64(32)
      end

      def find_session(req, sid)
        with_lock(req) do
          unless sid && (session = get_session(sid))
            sid = generate_sid
            session = {}
          end
          [sid, session]
        end
      end

      def write_session(req, sid, session, options)
        with_lock(req) do
          return false unless sid

          ttl = options[:expire_after] || @default_options[:expire_after]

          session_data = {
            data: session,
            created_at: session['_created_at'] || Time.now.to_i,
            updated_at: Time.now.to_i,
            identity_id: session['identity_id'],
            tenant_id: session['tenant_id'] || session['custid']
          }

          redis_key = "#{@redis_prefix}:#{sid}"

          begin
            Familia.dbclient.setex(
              redis_key,
              ttl.to_i,
              session_data.to_json
            )
            # Return a SessionId object for PersistedSecure
            ::Rack::Session::SessionId.new(sid, session)
          rescue => e
            OT.le "[RedisFamilia] Failed to write session: #{e.message}"
            false
          end
        end
      end

      def delete_session(req, sid, options)
        with_lock(req) do
          redis_key = "#{@redis_prefix}:#{sid}"
          Familia.dbclient.del(redis_key)
          generate_sid unless options[:drop]
        end
      end

      private

      def get_session(sid)
        redis_key = "#{@redis_prefix}:#{sid}"

        data = Familia.dbclient.get(redis_key)
        return nil unless data

        begin
          parsed = JSON.parse(data)
          parsed['data'] || {}
        rescue JSON::ParserError => e
          OT.le "[RedisFamilia] Failed to parse session data: #{e.message}"
          nil
        end
      end

      def with_lock(req, &block)
        @mutex.synchronize(&block)
      end
    end
  end
end
