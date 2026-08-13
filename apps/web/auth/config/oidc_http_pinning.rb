# apps/web/auth/config/oidc_http_pinning.rb
#
# frozen_string_literal: true

# DNS-rebinding guard for runtime OIDC egress (discovery, JWKS, token
# exchange) — the request-time half of the tenant-issuer SSRF story.
#
# WHY THIS EXISTS
#
#   Tenant-configured issuer URLs are validated when the SSO config is
#   SAVED (SsoConfig::SsrfProtection resolves the host and rejects
#   forbidden ranges). But the OIDC gems re-resolve DNS at REQUEST time:
#   omniauth_openid_connect -> openid_connect -> swd / webfinger /
#   rack-oauth2 each build their own Faraday connection and dial whatever
#   the hostname resolves to *now*. An attacker who controls the issuer's
#   DNS can pass save-time validation with a public A record, then flip
#   the record to 169.254.169.254 (or a loopback/internal address) before
#   the first discovery fetch — classic validate-then-re-resolve rebinding.
#
# WHY THIS SEAM
#
#   The Faraday connections live inside the gems (OpenIDConnect.http_client,
#   SWD.http_client, WebFinger, Rack::OAuth2.http_client); there is no app
#   callsite to wrap. The one supported hook is OpenIDConnect.http_config,
#   which yields each gem's Faraday builder. There we swap the adapter for
#   :net_http with a config block that Net::HTTP invokes per request
#   (faraday-net_http#configure_request), receiving the live Net::HTTP
#   instance BEFORE it connects. Setting `http.ipaddr = <validated ip>`
#   dials that exact IP while `http.address` (the hostname) still drives
#   the Host header, SNI, and certificate verification — resolution and
#   connection become one atomic, validated step.
#
#   This works because each gem's builder calls
#   `faraday.adapter Faraday.default_adapter` BEFORE invoking http_config,
#   and Faraday 2's RackBuilder#adapter REPLACES the adapter rather than
#   appending — so the adapter registered here wins.
#
# ORDERING CONSTRAINT (set-once + propagation-skip)
#
#   OpenIDConnect.http_config stores its block with `@@http_config ||=`
#   (SET-ONCE per process) and propagates it to SWD, WebFinger and
#   Rack::OAuth2 — but SKIPS any sub-protocol that already has a config.
#   Two consequences:
#
#     1. install! must run BEFORE any other http_config caller, or the
#        pinning silently never applies to some (or all) of the gems.
#        Today there is no other caller anywhere in the app; the spec
#        (spec/unit/oidc_http_pinning_spec.rb) locks in that after
#        install! all four modules share this exact block.
#     2. Re-running install! is harmless (`||=` keeps the first block),
#        so repeated config loads in tests are safe — but a re-run can
#        never REPLACE an earlier, different block. If a sub-protocol
#        ever reports a different http_config than OpenIDConnect, some
#        other caller won the race; find it and remove it.
#
# SINGLE-PIN BY DESIGN AT THIS SEAM
#
#   Guard.try_each_address! gives callers that own their dial loop a
#   reachability fallback across ALL validated addresses (webhook delivery
#   and SSO test-connection use it). This hook cannot: faraday-net_http
#   yields the live Net::HTTP instance exactly once, immediately before it
#   dials — falling back to a different address would mean re-running the
#   entire Faraday request, and this seam does not control the request
#   cycle (it spans four gems: OpenIDConnect, SWD, WebFinger, Rack::OAuth2).
#   pinned_address! prefers IPv4, which already sidesteps the common
#   broken-dual-stack failure mode (unreachable AAAA ahead of a healthy A).
#
# PROXY FAIL-CLOSED
#
#   `http.ipaddr=` controls the TCP dial target. Through a forward proxy
#   the PROXY makes the outbound connection and re-resolves the hostname
#   itself, so pinning is void. faraday-net_http passes an explicit nil
#   proxy unless a Faraday proxy is deliberately configured, so
#   `http.proxy_address` is only non-nil on purpose — and in that case we
#   refuse rather than silently un-pin.
#
# See: lib/onetime/http/guard.rb (blocklists + pinned_address!)
# See: apps/api/domains/logic/sso_config/ssrf_protection.rb
#      (the save-time half)

module Auth
  module OidcHttpPinning
    # Per-request Net::HTTP configuration, invoked by faraday-net_http with
    # the live connection object before it dials. Extracted as a constant so
    # the unit spec can drive it with a double instead of network fakery.
    ADAPTER_CONFIG = ->(http) do
      if http.proxy_address
        raise Onetime::Http::Guard::Blocked,
          'OIDC egress pinning cannot operate through a forward proxy; ' \
          'remove the proxy or disable SSO'
      end

      http.ipaddr = Onetime::Http::Guard.pinned_address!(http.address)
    end

    # The block handed to OpenIDConnect.http_config: replaces each gem's
    # default adapter with :net_http carrying ADAPTER_CONFIG.
    HTTP_CONFIG = ->(faraday) do
      faraday.adapter :net_http, &ADAPTER_CONFIG
    end

    # Install the pinning hook process-wide. Idempotent (see the ordering
    # note above). Called from Auth::Config::Features::OmniAuth.configure,
    # i.e. at boot, before any provider is registered and before any OIDC
    # traffic can occur — and only in processes that can serve SSO
    # (AUTHENTICATION_MODE=full with omniauth or org SSO enabled).
    def self.install!
      # openid_connect is a hard transitive dependency (via
      # omniauth_openid_connect in the Gemfile), required here rather than
      # at file load so merely loading the config tree stays gem-lazy.
      require 'openid_connect'

      OpenIDConnect.http_config(&HTTP_CONFIG)
    end
  end
end
