# lib/onetime/session/reauth_policy.rb
#
# frozen_string_literal: true

require 'uri'

require_relative 'surface'

module Onetime
  # Tenant-surface-compatible re-authentication policy (#4414, epic #4408).
  #
  # Recent full re-authentication (#4410) is a proof of *what happened*.
  # This module is the seam that answers *what a caller may offer* to make
  # that proof happen on the surface this request lives on. The re-auth UI
  # and the future re-auth POST endpoint both call {eligible_methods} and
  # render/accept exactly what it returns — no bespoke checks anywhere else.
  #
  # ## Why a surface-aware policy at all
  #
  # WebAuthn credentials are cryptographically bound to the origin (rp_id)
  # they were registered against. A passkey registered at the canonical
  # host cannot verify at `tenant.customer.com` — the browser refuses to
  # sign the challenge, and the server-side verify would reject even if it
  # did. That is the *floor*: a platform-only credential on an unrelated
  # tenant host is already unusable.
  #
  # The floor is not enough. A UI that renders a "Use security key" button
  # on a tenant surface, then fails the ceremony, is a dead-end that the
  # user reads as "the account has no valid path". So this module refuses
  # to *offer* the method too, and does so on the same evidence the server
  # would use to accept the ceremony:
  #
  #   - a credential is scoped to a surface at registration time (future
  #     wiring; today, all credentials read as :platform scope, which
  #     means "canonical-only");
  #   - a tenant deployment may opt into *related origins* — the W3C
  #     construct where an RP publishes /.well-known/webauthn declaring
  #     additional origins that share the rp_id — and a credential is then
  #     usable across the declared set;
  #   - otherwise, WebAuthn is offered only when the request's surface is
  #     canonical (the default rp_id).
  #
  # ## The four inputs
  #
  # {eligible_methods} takes a positional {SurfaceDescriptor}-shaped hash
  # (as {Onetime::SessionSurface.for_env} returns) and a keyword bag of
  # capability evidence:
  #
  #   surface:              — the request's resolved surface, or nil (invalid)
  #   password_enabled:     — install-level password sign-in capability
  #                           (already gated by AUTH_ENABLED / AUTH_SIGNIN
  #                           and per-tenant SigninConfig; a false here is
  #                           the ONE reason password is not offered)
  #   webauthn_credentials: — an array of credential descriptors:
  #                             { scope: :platform }
  #                             { scope: :tenant, id: '<CustomDomain#identifier>' }
  #                           (unknown scope symbols read as :platform)
  #   related_origins:      — exact origin + resolved surface members of the
  #                           configured related-origin set
  #   current_origin:       — exact browser origin for this request
  #
  # ## Fail-closed
  #
  # A nil surface (a host we do not serve, an unresolved :custom, or an
  # :invalid request whose surface could not be read; see
  # {Onetime::SessionSurface}) reads as "no path here":
  # {eligible_methods} returns []. A caller that gets [] must not offer
  # re-authentication at all — the alternative is a login-page redirect,
  # not a "click here and it will fail" UI.
  #
  # ## What this module does NOT decide
  #
  # It does not gate whether re-authentication is *required* (that is
  # {Onetime::RecentReauth.satisfied?}), and it does not verify a
  # completed ceremony (Rodauth does). It answers exactly one question:
  # given this surface and this account, which credential paths are safe
  # to *offer*?
  module ReauthPolicy
    # The credential-path tokens {eligible_methods} may return. Ordered by
    # UX preference — password last so the fallback is the last resort a
    # renderer places, not the first.
    METHODS = %w[webauthn password].freeze

    class << self
      # The credential paths this request's surface may present for re-auth.
      #
      # @param surface [Hash, nil] the resolved surface descriptor (as
      #   returned by {Onetime::SessionSurface.for_env})
      # @param password_enabled [Boolean] install-level password capability
      #   (caller has already intersected with tenant SigninConfig)
      # @param webauthn_credentials [Array<Hash>] the account's registered
      #   credentials with scope metadata (`{ scope: :platform | :tenant,
      #   id: <domain_id> }`); a bare `{}` reads as :platform
      # @param related_origins [Array<Hash>] `{ origin:, surface: }` members
      # @param current_origin [String, nil] exact browser origin
      # @return [Array<String>] ordered subset of {METHODS}
      def eligible_methods(surface, password_enabled:, webauthn_credentials:, related_origins: [], current_origin: nil)
        return [] if surface.nil?

        methods = []
        if webauthn_offerable?(surface, webauthn_credentials, related_origins, current_origin: current_origin)
          methods << 'webauthn'
        end
        methods << 'password' if password_enabled == true
        methods.freeze
      end

      # True iff at least one of the account's WebAuthn credentials would
      # be presentable on this request's surface.
      #
      # Positive cases, with no widening default:
      #
      #   1. The surface is :canonical AND the account has any credential
      #      registered under the platform (:platform) scope. This is the
      #      default deployment: a passkey registered on the canonical host
      #      lives at rp_id = canonical, so it verifies on canonical
      #      requests and no others.
      #
      #   2. The surface is :subdomain or :custom AND the account has a
      #      credential explicitly scoped to this surface whose stored RP ID
      #      equals the current request host.
      #
      #   3. The request's surface belongs to a related-origins set the
      #      RP has declared (a non-empty `related_origins` set), AND the
      #      account has a credential registered on one of the *other*
      #      surfaces in that set. This is the only branch where a
      #      credential registered elsewhere may be offered here, and the
      #      exact origin is a member, and the credential's stored RP ID names
      #      its registration member. Scheme and port remain significant.
      #
      # @param surface [Hash] the resolved surface descriptor
      # @param credentials [Array<Hash>] the account's WebAuthn credentials
      # @param related_origins [Array<Hash>] `{ origin:, surface: }` members
      # @return [Boolean]
      def webauthn_offerable?(surface, credentials, related_origins, current_origin: nil)
        credentials = Array(credentials)
        return false if credentials.empty?

        current_rp_id = origin_host(current_origin)
        if credentials.any? { |credential| directly_usable?(credential, surface, current_rp_id) }
          return true
        end

        current_origin = normalize_origin(current_origin)
        return false if current_origin.nil?

        related = Array(related_origins).filter_map { |entry| related_origin_entry(entry) }
        return false unless related.any? do |entry|
          entry[:origin] == current_origin && surfaces_equal?(entry[:surface], surface)
        end

        credentials.any? do |credential|
          rp_id = credential[:rp_id] || credential['rp_id']
          next false if rp_id.to_s.empty?

          related.any? do |entry|
            entry[:origin] != current_origin &&
              origin_host(entry[:origin]) == rp_id.to_s.downcase &&
              credential_matches_surface?(credential, entry[:surface])
          end
        end
      end

      # Whether a single credential's registration scope matches a
      # surface. Unknown scope symbols read as :platform (the historical
      # default; a nil/missing `scope` on a legacy row is not a tenant
      # credential).
      #
      # @param credential [Hash] `{ scope:, id: }`
      # @param surface [Hash] a surface descriptor
      # @return [Boolean]
      def credential_matches_surface?(credential, surface)
        return false unless credential.is_a?(Hash) && surface.is_a?(Hash)

        scope = credential[:scope] || credential['scope']
        scope = scope.to_sym if scope.respond_to?(:to_sym)
        scope = :platform unless [:tenant, :subdomain].include?(scope)

        kind = (surface['kind'] || surface[:kind]).to_s

        case scope
        when :platform
          kind == 'canonical'
        when :subdomain
          credential_host = credential[:host] || credential['host']
          surface_host    = surface['host'] || surface[:host]
          kind == 'subdomain' && !credential_host.to_s.empty? &&
            credential_host.to_s.downcase == surface_host.to_s.downcase
        when :tenant
          # Tenant credentials are bound to a specific custom-domain
          # identifier (the :custom surface's :id). Subdomain surfaces
          # cannot host a tenant credential in this model — a subdomain
          # deployment shares the canonical rp_id unless it publishes a
          # related-origins declaration, and that path is handled by
          # the related_origins argument above.
          return false unless kind == 'custom'

          credential_id = credential[:id] || credential['id']
          surface_id    = surface['id'] || surface[:id]
          !credential_id.to_s.empty? && credential_id.to_s == surface_id.to_s
        end
      end

      private

      def directly_usable?(credential, surface, current_rp_id)
        return false unless credential_matches_surface?(credential, surface)

        rp_id = credential[:rp_id] || credential['rp_id']
        return legacy_platform_credential?(credential, surface) if rp_id.to_s.empty?
        return false if current_rp_id.nil?

        rp_id.to_s.downcase == current_rp_id
      end

      def legacy_platform_credential?(credential, surface)
        scope = credential[:scope] || credential['scope']
        kind  = surface[:kind] || surface['kind']
        ![:tenant, :subdomain].include?(scope&.to_sym) && kind.to_s == 'canonical'
      end

      def related_origin_entry(entry)
        return nil unless entry.is_a?(Hash)

        origin  = normalize_origin(entry[:origin] || entry['origin'])
        surface = entry[:surface] || entry['surface']
        return nil if origin.nil? || !surface.is_a?(Hash)

        { origin: origin, surface: surface }
      end

      def normalize_origin(value)
        uri = URI.parse(value.to_s)
        return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return nil if uri.host.to_s.empty?
        return nil unless uri.path.to_s.empty? || uri.path == '/'
        return nil unless uri.query.nil? && uri.fragment.nil? && uri.userinfo.nil?

        scheme    = uri.scheme.downcase
        host      = uri.host.downcase
        default   = scheme == 'https' ? 443 : 80
        authority = uri.port == default ? host : "#{host}:#{uri.port}"
        "#{scheme}://#{authority}"
      rescue URI::InvalidURIError
        nil
      end

      def origin_host(origin)
        normalized = normalize_origin(origin)
        normalized && URI.parse(normalized).host.to_s.downcase
      end

      def surfaces_equal?(left, right)
        return false unless left.is_a?(Hash) && right.is_a?(Hash)

        left.transform_keys(&:to_s).transform_values(&:to_s) ==
          right.transform_keys(&:to_s).transform_values(&:to_s)
      end
    end
  end
end
