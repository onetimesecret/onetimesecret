# apps/web/auth/routes/reauth.rb
#
# frozen_string_literal: true

require 'onetime/security/login_rate_limiter'

require_relative 'json_body'
require_relative '../operations/reauth_offer'
require_relative '../operations/reauthenticate'

module Auth
  module Routes
    # JSON API for the tenant-surface-compatible re-authentication offer
    # (#4414, epic #4408).
    #
    # The Vue re-auth component reads GET /auth/reauth-offer before it
    # renders a form. POST /auth/reauth rebuilds that same offer before
    # accepting a method, keeping presentation and verification aligned.
    #
    # SECURITY:
    #   - Authentication is REQUIRED: the offer is per-account state,
    #     and returning it to an anonymous caller would leak whether an
    #     account has WebAuthn credentials and how many.
    #   - The offer's credentials projection carries ONLY the shape
    #     ReauthPolicy consumes (`{scope:}` / `{scope:, id:}`) — never
    #     public keys, sign counters, or credential ids. Even so, we
    #     scope it strictly to `rodauth.session_value` so a
    #     misconfigured caller cannot ask for another account's offer.
    #   - The endpoint is deliberately CACHE-HOSTILE: the offer depends
    #     on session, request host, and account state, so we set
    #     Cache-Control: no-store to keep intermediary caches from
    #     laundering one account's offer to another viewer.
    module Reauth
      include Onetime::Security::LoginRateLimiter
      include Auth::Routes::JsonBody

      # Wire descriptor projection — the resolver returned Symbol keys
      # (`kind: :canonical`), and while JSON.serialize coerces symbols
      # to strings on the way out, being explicit here is one less
      # place a downstream consumer has to guess. Nil surface passes
      # through as JSON null.
      def self.serialize_surface(surface)
        return nil if surface.nil?

        surface.transform_values { |v| v.is_a?(Symbol) ? v.to_s : v }
          .transform_keys(&:to_s)
      end

      # The credentials projection is already the shape ReauthPolicy
      # consumes. Serialize scope as a string for consistency with the
      # wire convention.
      def self.serialize_credentials(credentials)
        credentials.map do |c|
          {
            'scope' => c[:scope].to_s,
            'id' => c[:id],
          }.compact
        end
      end

      def handle_reauth_routes(r)
        r.on 'reauth-offer' do
          account_id = reauth_account_id
          next reauth_unauthorized unless account_id

          r.get do
            reauth_no_store!
            offer = build_reauth_offer(account_id)

            {
              'surface' => Auth::Routes::Reauth.serialize_surface(offer[:surface]),
              'methods' => offer[:methods],
              'webauthn_credentials' => Auth::Routes::Reauth.serialize_credentials(offer[:webauthn_credentials]),
              'related_origins' => offer[:related_origins].map { |s| Auth::Routes::Reauth.serialize_surface(s) },
            }
          rescue StandardError => ex
            reauth_failure(ex, account_id, 'offer')
          end
        end

        r.on 'reauth' do
          account_id = reauth_account_id
          next reauth_unauthorized unless account_id

          r.post do
            reauth_no_store!
            params  = json_body_object(request)
            offer   = build_reauth_offer(account_id)
            account = rodauth.account_from_session

            if params['method'].to_s == 'password' && account
              check_login_rate_limit!(account[:email], request.ip)
            end

            result = Auth::Operations::Reauthenticate.new(
              rodauth.db,
              rodauth: rodauth,
              session: session,
              env: request.env,
            ).call(account_id: account_id, offer: offer, params: params)

            if params['method'].to_s == 'password' && account
              if result.password_verified
                clear_login_rate_limit!(account[:email], request.ip)
              elsif result.body['error_code'] == 'invalid_password'
                record_failed_login_attempt!(account[:email], request.ip)
              end
            end

            response.status = result.status
            result.body
          rescue Onetime::LimitExceeded => ex
            response.status                 = 429
            response.headers['Retry-After'] = ex.retry_after.to_s if ex.retry_after
            {
              'error' => 'Too many attempts. Please try again later.',
              'error_code' => 'reauth_rate_limited',
              'retry_after' => ex.retry_after,
            }
          rescue StandardError => ex
            reauth_failure(ex, account_id, 'completion')
          end
        end
      end

      private

      def reauth_account_id
        return nil unless rodauth.logged_in?

        rodauth.session_value
      end

      def reauth_unauthorized
        response.status = 401
        { 'error' => 'Authentication required' }
      end

      def reauth_no_store!
        response.headers['Cache-Control'] = 'no-store'
        response.headers['Pragma']        = 'no-cache'
      end

      def build_reauth_offer(account_id)
        Auth::Operations::ReauthOffer.new(rodauth.db).call(
          account_id: account_id,
          env: request.env,
        )
      end

      def reauth_failure(exception, account_id, phase)
        Onetime.get_logger('Auth::Reauth').error "Error during reauth #{phase}",
          account_id: account_id,
          error: exception.message,
          error_class: exception.class.name

        response.status = 500
        message         = phase == 'offer' ? 'Failed to build reauth offer' : 'Failed to complete re-authentication'
        { 'error' => message }
      end
    end
  end
end
