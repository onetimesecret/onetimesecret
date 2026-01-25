# lib/onetime/initializers/check_redis_url.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # Validates that the Redis/Valkey URL is properly configured and does not
    # contain placeholder values. This fail-fast check prevents confusing
    # downstream errors like "Cannot connect to redis redis://CHANGEME@..."
    #
    # Must be called after config is loaded but before connect_databases.
    #
    def check_redis_url
      redis_uri = OT.conf.dig(:redis, :uri)

      if redis_uri.nil? || redis_uri.to_s.strip.empty?
        raise OT::Problem, <<~MSG
          Redis/Valkey URI is not configured.
          Set REDIS_URL or VALKEY_URL environment variable, or configure redis.uri in etc/config.yaml
        MSG
      end

      if redis_uri.to_s.include?('CHANGEME')
        raise OT::Problem, <<~MSG
          Redis/Valkey URI contains placeholder 'CHANGEME': #{redis_uri}
          Set REDIS_URL or VALKEY_URL environment variable to the actual Redis/Valkey service URL.
          Example: redis://localhost:6379/0 or redis://password@redis-host:6379/0
        MSG
      end

      OT.ld "[check_redis_url] Redis URI validated: #{redis_uri.sub(/:[^:@]+@/, ':***@')}"
    end
  end
end
