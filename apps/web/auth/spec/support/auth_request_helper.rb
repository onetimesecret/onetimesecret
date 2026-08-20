# apps/web/auth/spec/support/auth_request_helper.rb
#
# frozen_string_literal: true

require_relative 'auth_test_constants'

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
  # The full mounted Rack stack, as Rack::Test::Methods requires. Eight specs
  # carried this identical one-liner; a group that needs different construction
  # (e.g. basicauth_rejection_on_session_routes_spec.rb, which memoizes around
  # a Registry.reset!) still defines its own and wins on ancestor order.
  #
  # The empty-registry guard is what a per-spec copy used to buy implicitly: a
  # group that never boots gets an EMPTY Rack::URLMap rather than an error, and
  # every request in it 404s. Auto-inclusion means no author is forced to think
  # about mounting any more, so the check has to be here — a named harness
  # failure instead of a spec that reads as "the route is broken".
  #
  # Registry.rack_url_map, NOT generate_rack_url_map. Rack::Test asks for `app`
  # once per EXAMPLE, and generate_rack_url_map re-instantiates every
  # registered application — the whole middleware stack of each, plus warmup.
  # Beyond the cost, the rebuild reverts class-level middleware state: it fires
  # lazily on the example's FIRST request, so it lands AFTER the before hooks.
  # DomainStrategy#initialize re-runs initialize_from_config(OT.conf…) on every
  # instantiation, which is how a hook's assignment to that class state
  # vanished between the hook and the assertion (#4221). The cached accessor
  # invalidates itself on registry mutation and on a config swap, so the files
  # that re-boot in before(:all) still get a fresh mount — see
  # lib/onetime/application/registry.rb.
  def app
    if Onetime::Application::Registry.mount_mappings.empty?
      raise 'Application registry has no mounts, so `app` would be an empty ' \
            'Rack::URLMap and every request in this group would 404. The group ' \
            'needs a before(:all) that calls Onetime.boot! then ' \
            'Onetime::Application::Registry.prepare_application_registry.'
    end

    Onetime::Application::Registry.rack_url_map
  end

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

  # Establish an authenticated session through the real login route.
  #
  # The status assertion is a PRECONDITION, not the subject of any caller: a
  # silently failed login here surfaces three lines later as a confusing 401 on
  # the route actually under test. 200 (JSON) and 302 (HTML redirect) are both
  # success — which one comes back depends on the Accept negotiation.
  def csrf_login(email, password: AuthTestConstants::TEST_PASSWORD)
    csrf_json_post('/auth/login', login: email, password: password)
    expect(last_response.status).to be_between(200, 302),
      "Precondition failed: login for #{email} returned #{last_response.status}: #{last_response.body}"
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
