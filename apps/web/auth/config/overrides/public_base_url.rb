# apps/web/auth/config/overrides/public_base_url.rb
#
# frozen_string_literal: true

require_relative '../../lib/public_host'

module Auth::Config::Overrides
  # Build Rodauth's absolute URLs from the request's PUBLIC host (#4221).
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
  # Overriding `base_url` rather than `domain` is deliberate: `domain` also
  # feeds `email_from`'s "webmaster@" default, the OTP issuer, and the SMS
  # message bodies, none of which should follow the request host. It also
  # keeps the internal_request contract intact — internal requests carry no
  # display domain, so they fall through to `super()` and still raise the
  # "must set domain in configuration" error rather than inventing a host.
  #
  # Auth::PublicHost carries the trust argument (why `display_domain` and not
  # the raw forwarded header, why canonical-set hosts are excluded); the short
  # version is that reading an unvalidated header here would reopen
  # reset-password link poisoning.
  #
  module PublicBaseUrl
    def self.configure(auth)
      # `super()` with explicit parens is required: this block becomes a
      # define_method body, where bare zsuper is a RuntimeError.
      auth.base_url do
        Auth::PublicHost.base_url(request.env) || super()
      end

      # rubocop:disable Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # The host to SHOW in transactional email (branding, "you're signing
        # in to X"). Must be the same host the link in that email points at,
        # so it reads through the same resolver; falls back to the request
        # authority when there is no resolved display domain.
        #
        # @return [String]
        def public_display_domain
          Auth::PublicHost.resolve(request.env) || request.host
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition
    end
  end
end
