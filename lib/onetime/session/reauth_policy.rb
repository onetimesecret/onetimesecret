# lib/onetime/session/reauth_policy.rb
#
# frozen_string_literal: true

require 'onetime/session/surface'

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
  #   related_origins:      — an array of surface descriptors the request's
  #                           surface belongs to a related-origins set with
  #                           (never widens without positive evidence; an
  #                           empty array means no related-origins deployment)
  #
  # ## Fail-closed
  #
  # A nil surface (:invalid, unresolved :custom) reads as "no path here":
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
      # @param related_origins [Array<Hash>] surface descriptors the
      #   request's surface belongs to a related-origins set with; an
      #   empty array means no related-origins deployment
      # @return [Array<String>] ordered subset of {METHODS}
      def eligible_methods(surface, password_enabled:, webauthn_credentials:, related_origins: [])
        return [] if surface.nil?

        methods = []
        methods << 'webauthn' if webauthn_offerable?(surface, webauthn_credentials, related_origins)
        methods << 'password' if password_enabled == true
        methods.freeze
      end

      # True iff at least one of the account's WebAuthn credentials would
      # be presentable on this request's surface.
      #
      # THREE positive cases, and no widening default:
      #
      #   1. The surface is :canonical AND the account has any credential
      #      registered under the platform (:platform) scope. This is the
      #      default deployment: a passkey registered on the canonical host
      #      lives at rp_id = canonical, so it verifies on canonical
      #      requests and no others.
      #
      #   2. The surface is :subdomain or :custom AND the account has a
      #      credential explicitly scoped to *this* surface. Per-surface
      #      credential storage is future wiring (#4137 in the sibling
      #      thread); until then, no credential carries the :tenant scope
      #      and this branch never fires for a real credential.
      #
      #   3. The request's surface belongs to a related-origins set the
      #      RP has declared (a non-empty `related_origins` set), AND the
      #      account has a credential registered on one of the *other*
      #      surfaces in that set. This is the only branch where a
      #      credential registered elsewhere may be offered here, and the
      #      caller-supplied set is the ONLY evidence — an empty set is
      #      the safe default.
      #
      # @param surface [Hash] the resolved surface descriptor
      # @param credentials [Array<Hash>] the account's WebAuthn credentials
      # @param related_origins [Array<Hash>] surface descriptors the
      #   request's surface belongs to a related-origins set with
      # @return [Boolean]
      def webauthn_offerable?(surface, credentials, related_origins)
        credentials = Array(credentials)
        return false if credentials.empty?

        return true if credentials.any? { |c| credential_matches_surface?(c, surface) }

        related = Array(related_origins).compact
        return false if related.empty?

        # Related-origins acceptance requires the CURRENT surface to be a
        # declared member of the set — the RP has published that this
        # origin is part of the group. Without that membership, the set
        # is not evidence about the current surface at all: an operator
        # who declares canonical+tenant-a as a related-origins group has
        # said nothing about tenant-b, and a credential registered on
        # canonical must NOT be laundered into acceptance there.
        return false unless related.include?(surface)

        # Now the credential must be registered on one of the OTHER
        # declared surfaces. `credential_matches_surface?` decides that
        # per-surface — so the same evidence rule fires (a :platform
        # credential matches a :canonical declared surface; a :tenant
        # credential matches its own :custom declared surface). The
        # current surface is intentionally NOT re-tested here; if a
        # credential matched it we'd have returned true above.
        related.any? do |related_surface|
          next false if related_surface == surface

          credentials.any? { |c| credential_matches_surface?(c, related_surface) }
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
        scope = :platform unless scope == :tenant

        case scope
        when :platform
          surface[:kind] == :canonical
        when :tenant
          # Tenant credentials are bound to a specific custom-domain
          # identifier (the :custom surface's :id). Subdomain surfaces
          # cannot host a tenant credential in this model — a subdomain
          # deployment shares the canonical rp_id unless it publishes a
          # related-origins declaration, and that path is handled by
          # the related_origins argument above.
          return false unless surface[:kind] == :custom

          credential_id = credential[:id] || credential['id']
          !credential_id.to_s.empty? && credential_id.to_s == surface[:id].to_s
        end
      end
    end
  end
end
