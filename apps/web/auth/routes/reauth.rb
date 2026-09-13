# apps/web/auth/routes/reauth.rb
#
# frozen_string_literal: true

require_relative '../operations/reauth_offer'

module Auth
  module Routes
    # JSON API for the tenant-surface-compatible re-authentication offer
    # (#4414, epic #4408).
    #
    # The Vue re-auth component polls GET /auth/reauth-offer before it
    # renders a form — the returned `methods` list is the ONLY thing it
    # may present as a button, and the same list is the ONLY thing the
    # future POST /auth/reauth handler will accept. That symmetry is
    # what keeps tenant safety from drifting between UI and endpoint.
    #
    # SCOPE — GET-ONLY here. The completion side (POST /auth/reauth)
    # requires WebAuthn challenge/verify plumbing that is a separate
    # commit; this route lands the read half so the UI can be wired
    # against it without being blocked on the write half.
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
          unless rodauth.logged_in?
            response.status = 401
            next { error: 'Authentication required' }
          end

          account_id = rodauth.session_value
          unless account_id
            response.status = 401
            next { error: 'Invalid session' }
          end

          r.get do
            response.headers['Cache-Control'] = 'no-store'
            response.headers['Pragma']        = 'no-cache'

            offer = Auth::Operations::ReauthOffer.new(rodauth.db).call(
              account_id: account_id,
              env: request.env,
            )

            {
              'surface' => Auth::Routes::Reauth.serialize_surface(offer[:surface]),
              'methods' => offer[:methods],
              'webauthn_credentials' => Auth::Routes::Reauth.serialize_credentials(offer[:webauthn_credentials]),
              'related_origins' => offer[:related_origins].map { |s| Auth::Routes::Reauth.serialize_surface(s) },
            }
          rescue StandardError => ex
            Onetime.get_logger('Auth::Reauth').error 'Error building reauth offer',
              account_id: account_id,
              error: ex.message,
              error_class: ex.class.name

            response.status = 500
            { error: 'Failed to build reauth offer' }
          end
        end
      end
    end
  end
end
