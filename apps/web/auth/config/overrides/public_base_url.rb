# apps/web/auth/config/overrides/public_base_url.rb
#
# frozen_string_literal: true

require_relative '../../lib/public_host'

module Auth::Config::Overrides
  # Build Rodauth's absolute URLs from the request's PUBLIC host (#4221),
  # allowlisted to registered tenant hosts (finding G-01).
  #
  # `base_url` is `"#{request.scheme}://#{domain}"` and `domain` is
  # `request.host` (rodauth 2.45 base.rb:562). Behind the custom-domain proxy
  # `Host:` has been rewritten to the origin target and the host the visitor
  # actually used travels in headers only, so every URL Rodauth composes names
  # the wrong site. Two consumers, both user-visible:
  #
  #   1. `token_link` → `route_url` → `base_url` (email_base.rb:54): the
  #      magic-link, reset-password, verify-account, verify-login-change and
  #      unlock email links. A custom-domain user asks for a magic link on
  #      nz.example.com and receives a link to the canonical host — where
  #      Auth::SigninGate rejects :email_auth with the router's byte-identical
  #      404 on any install whose global signin is off (tenant-only signin).
  #      Even where the canonical host does allow signin, the session lands on
  #      the wrong origin.
  #   2. `webauthn_origin` (webauthn.rb:337): the origin a passkey assertion is
  #      verified against. The browser signs the origin it is ON — the display
  #      domain — so on a custom domain the stock value cannot match.
  #
  # ## Finding G-01: the fallback must be the CANONICAL host, never request.host
  #
  # Rodauth's stock `base_url` reads `Rack::Request#host`, and Rack 3.2
  # resolves that through `forwarded_authority` FIRST — it honors a
  # client-settable `X-Forwarded-Host` / `Forwarded` header from ANY client,
  # ungated by proxy trust. So on an ordinary canonical-host request, where
  # Auth::PublicHost.base_url declines, `super()` would build the link on
  # whatever host the client forged. That is reset-link poisoning → account
  # takeover. Both overrides below therefore fall back to the request-
  # independent CANONICAL host (Auth::PublicHost.canonical_base_url /
  # .canonical_host), so no auth-URL host is ever derived from request.host.
  # (A Rack middleware, Onetime::Middleware::StripForwardedHost, deletes the
  # forwarded-host headers at the stack edge too — defense in depth.)
  #
  # `super()` is kept only as a last resort BEHIND the canonical value: it is
  # reached only when site.host is entirely unconfigured, which is exactly the
  # "must set domain in configuration" misconfiguration Rodauth's internal
  # requests are meant to raise on. In every configured deployment the
  # canonical value wins and super() is dead.
  #
  # Overriding `base_url` rather than `domain` is deliberate: `domain` also
  # feeds `email_from`'s "webmaster@" default, the OTP issuer, and the SMS
  # message bodies, none of which should follow the request host.
  #
  # Auth::PublicHost carries the trust argument (why `display_domain` and not
  # the raw forwarded header, why a registered-tenant record is required, why
  # a datastore blip fails closed).
  #
  module PublicBaseUrl
    def self.configure(auth)
      # `super()` with explicit parens is required: this block becomes a
      # define_method body, where bare zsuper is a RuntimeError.
      auth.base_url do
        Auth::PublicHost.base_url(request.env) ||
          Auth::PublicHost.canonical_base_url ||
          super()
      end

      # rubocop:disable Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # The host to SHOW in transactional email (branding, "you're signing
        # in to X"). Must be the same host the link in that email points at,
        # so it reads through the same resolver; falls back to the CANONICAL
        # host — never the request authority — when there is no resolved
        # tenant display domain (finding G-01).
        #
        # @return [String]
        def public_display_domain
          Auth::PublicHost.resolve(request.env) || Auth::PublicHost.canonical_host
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition
    end
  end
end
