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
  # takeover. Both overrides below therefore never derive a host from
  # request.host: the fallback tiers are the request's OWN canonical host
  # (Auth::PublicHost.canonical_request_host — a trusted candidate accepted
  # only when it is a member of the canonical set, so a split deployment's
  # secondary canonical host keeps its links on itself), then the
  # request-independent configured host (canonical_base_url / canonical_host).
  # That chain is Auth::PublicHost.allowlisted_base_url / allowlisted_host,
  # and OmniAuth's `full_host` resolver reads the very same chain (#4517), so
  # an SSO redirect_uri and an email link for one request can never disagree
  # about the host. (A Rack middleware, Onetime::Middleware::StripForwardedHost,
  # deletes the forwarded-host headers at the stack edge too — defense in
  # depth.)
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
    module ResetPasswordOrigin
      # Also protect direct/internal key creation, before INSERT or updating an
      # existing key's email_last_sent; an email-time failure alone is too late.
      def create_reset_password_key
        base_url
        super
      end
    end

    def self.configure(auth)
      # `super()` with explicit parens is required: this block becomes a
      # define_method body, where bare zsuper is a RuntimeError.
      auth.base_url do
        Auth::PublicHost.allowlisted_base_url(request.env) || super()
      end

      auth_class = auth.instance_variable_get(:@auth)
      if auth_class&.features&.include?(:reset_password)
        auth.auth_class_eval { prepend Auth::Config::Overrides::PublicBaseUrl::ResetPasswordOrigin }
      end

      # rubocop:disable Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # The host to SHOW in transactional email (branding, "you're signing
        # in to X"). Must be the same host the link in that email points at,
        # so it reads through the same resolver; falls back to a CANONICAL
        # host — the request's own canonical host first, then the configured
        # one, never the request authority — when there is no resolved tenant
        # display domain (finding G-01).
        #
        # @return [String]
        def public_display_domain
          Auth::PublicHost.allowlisted_host(request.env)
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition
    end
  end
end
