# lib/onetime/application/auth_strategies/helpers.rb
#
# frozen_string_literal: true

require 'rack/request'
require 'otto'

#
# Shared helper methods for authentication strategies.
#
# Provides common functionality for loading users from sessions
# and building metadata hashes for auth results.
#
# @see Onetime::Application::AuthStrategies

module Onetime
  module Application
    module AuthStrategies
      # Shared helper methods for authentication strategies
      module Helpers
        # Loads customer from session if authenticated
        #
        # @param session [Hash] Rack session
        # @return [Onetime::Customer, nil] Customer if found, nil otherwise
        def load_user_from_session(session)
          return nil unless session
          return nil unless session['authenticated'] == true

          external_id = session['external_id']
          return nil if external_id.to_s.empty?

          Onetime::Customer.find_by_extid(external_id)
        rescue StandardError => ex
          OT.le "[auth_strategy] Failed to load customer: #{ex.message}"
          OT.ld ex.backtrace.first(3).join("\n")
          nil
        end

        # Builds standard metadata hash from env
        #
        # @param env [Hash] Rack environment
        # @param additional [Hash] Additional metadata to merge
        # @return [Hash] Metadata hash
        def build_metadata(env, additional = {})
          {
            ip: client_ip(env),
            user_agent: env['HTTP_USER_AGENT'],
            domain_strategy: env['onetime.domain_strategy'],
            display_domain: env['onetime.display_domain'],
          }.merge(additional)
        end

        private

        # Resolve the client IP for auth metadata.
        #
        # Prefers env['otto.client_ip'], the value resolved once by the universal
        # IPPrivacyMiddleware mount (trusted-proxy / depth resolution from
        # site.network.trusted_proxy, then privacy masking). Falls back to
        # Otto::Utils.resolve_client_ip when the middleware has not run (e.g. a
        # standalone auth strategy invocation in a unit test), so the trusted-proxy
        # contract holds even without the full stack. Bare Rack::Request#ip is the
        # last resort.
        #
        # @param env [Hash] Rack environment
        # @return [String, nil] resolved client IP
        def client_ip(env)
          canonical = env['otto.client_ip']
          return canonical if canonical && !canonical.empty?

          Otto::Utils.resolve_client_ip(env, env['otto.security_config'])
        rescue StandardError
          Rack::Request.new(env).ip
        end
      end
    end
  end
end
