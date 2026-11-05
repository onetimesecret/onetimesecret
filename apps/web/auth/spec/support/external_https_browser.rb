# apps/web/auth/spec/support/external_https_browser.rb
#
# frozen_string_literal: true

# =============================================================================
# External HTTPS browser model for Rack::Test
# =============================================================================
#
# An opt-in cookie jar for specs that simulate a deployment behind a
# TLS-terminating proxy: the browser reaches the proxy over https, and what
# the proxy tells the application about the scheme (X-Forwarded-Proto, or
# nothing) is the example's to send.
#
# WHY. Onetime::Session#set_cookie adds Secure to the session cookie on
# every request the application sees as https, including one a trusted
# proxy forwards with X-Forwarded-Proto: https (audit L-1). Rack::Test's
# cookie jar applies the Secure attribute the way a browser does: a Secure
# cookie is stored and sent only for an https request URI (Rack::Test::Cookie
# #valid?). A spec that sends X-Forwarded-Proto: https on a relative path
# therefore talks to the app over Rack::Test's default http://example.org,
# receives a Secure session cookie, and never sends it back. The next
# request arrives with no session: no CSRF token (Rack::Protection's plain
# 403 before any route), no pending AuthnRequest (saml_no_pending_request),
# no login. That is the right behaviour for a browser on http, and the wrong
# model for the browser these specs describe, which is on https.
#
# WHAT IT CHANGES. Only the scheme the jar evaluates cookies against: every
# cookie is stored and offered as if the request URI were https. Everything
# else the jar enforces stays as Rack::Test enforces it (Domain and Path
# matching, expiry, replacement by name, domain and path), and a Secure
# cookie still needs that https leg; the model supplies it, nothing else
# does.
#
# WHAT IT LEAVES ALONE. The Rack environment. No HTTPS=on, no rack.url_scheme
# change, no header: the application sees exactly the scheme the example
# sends, so rows that check what an untrusted peer's X-Forwarded-Proto does,
# what Set-Cookie attributes a response carries, or what a request without
# the header is treated as, keep their meaning. A spec that wants the app
# itself to see https still says so with the header or an https:// URL.
#
# Rack::Test does not enforce SameSite; this does not add it.
#
# USE. Include the shared context (or the module) in the example group:
#
#   include_context 'external HTTPS browser'
#
# Rack::Test::Methods builds its sessions through build_rack_mock_session
# when the group defines it, whichever module was included first, so the
# opt-in cannot be undone by include order. clear_cookies keeps the model.
# =============================================================================

require 'rack/test'
require 'uri'

module ExternalHttpsBrowser
  # Rack::Test::CookieJar whose requests are, to the jar, always https.
  class CookieJar < Rack::Test::CookieJar
    # The Cookie header for +uri+, Secure cookies included.
    def for(uri)
      super(external(uri))
    end

    # Store +raw_cookies+ set in response to a request for +uri+, Secure
    # cookies included.
    def merge(raw_cookies, uri = nil)
      super(raw_cookies, external(uri))
    end

    private

    # +uri+ as the browser's https leg sees it. Host and path are untouched,
    # so Domain and Path matching are the jar's own. A nil +uri+ is the
    # jar's default, as in Rack::Test (set_cookie without a URI).
    def external(uri)
      uri = uri ? uri.dup : URI.parse("//#{@default_host}/")
      uri.scheme = 'https'
      uri
    end
  end

  # Rack::Test::Session that starts with, and clears to, the jar above.
  class Session < Rack::Test::Session
    def clear_cookies
      @cookie_jar = ExternalHttpsBrowser::CookieJar.new([], @default_host)
    end
  end

  # The hook Rack::Test::Methods#build_rack_test_session consults before
  # building a plain Session, by name (it is respond_to?-checked, not
  # inherited), so the first-included module does not decide.
  def build_rack_mock_session
    host = respond_to?(:default_host) ? default_host : Rack::Test::DEFAULT_HOST
    ExternalHttpsBrowser::Session.new(app, host)
  end
end

if defined?(RSpec)
  RSpec.shared_context 'external HTTPS browser' do
    include ExternalHttpsBrowser
  end
end
