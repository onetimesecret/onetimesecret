# apps/web/auth/spec/support/auth_request_helper.rb
#
# frozen_string_literal: true

# =============================================================================
# CSRF-aware request plumbing (auto-included into `type: :integration`)
# =============================================================================
#
# Every Rodauth POST in this app needs shrimp — the token in BOTH the
# X-CSRF-Token header and the JSON body — and every request after a POST needs
# the body headers cleared, because Rack::Test keeps `Content-Type` and
# `Content-Length` sticky across calls and a GET carrying a stale
# `Content-Length` is answered as a truncated/blank body.
#
# ProductionConfigHelper#json_post (spec_helper.rb) predates all of that and is
# CSRF-blind: no shrimp, no header clearing. It stays as-is — a dozen specs
# post to non-Rodauth routes through it. This module is the CSRF-aware path,
# under DIFFERENT names, so the two never resolve against each other by
# ancestor order.
#
# Auto-included, so a new integration spec gets the shared path for free
# rather than growing an eighth copy (the copy counts before this file:
# fetch_csrf_token 6, clear_body_headers 5, json_body 3).
#
# A group that defines any of these itself still wins — a `def` in the example
# group body sits below config-included modules in the ancestor chain.
#
# =============================================================================

module AuthRequestHelper
  # Drop the sticky body headers Rack::Test carries over from a previous POST.
  # Call before any GET, and before a POST whose body length differs.
  def clear_body_headers
    header 'Content-Type', nil
    header 'Content-Length', nil
  end

  # GET /auth purely to read the CSRF token off the response headers.
  def fetch_csrf_token
    clear_body_headers
    header 'Accept', 'application/json'
    get '/auth'
    last_response.headers['X-CSRF-Token']
  end

  # JSON POST with the CSRF token in both the header and the body (shrimp),
  # matching what the SPA sends and what the Rodauth routes require.
  def csrf_json_post(path, params = {})
    csrf = fetch_csrf_token
    clear_body_headers
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf if csrf
    post path, JSON.generate(params.merge(shrimp: csrf))
    last_response
  end

  # Parse the last response body as JSON.
  #
  # Raises (rather than returning {}) on a non-JSON body: every caller asserts
  # the status first, so a parse failure here means the response was not the
  # one the spec thinks it got, and an empty hash would surface that as a
  # confusing nil three lines later.
  def json_body
    JSON.parse(last_response.body)
  rescue JSON::ParserError => e
    raise JSON::ParserError,
      "Response body is not JSON (#{last_response.status}): #{last_response.body.to_s[0, 300].inspect} (#{e.message})"
  end
end
