# spec/integration/full/routes/resend_verification_email_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Anti-enumeration contract for POST /api/account/resend-verification-email.
#
# These tests make REAL HTTP requests to the mounted Rack application via
# Rack::Test (the `auth_rack_test` shared context) and assert the FROZEN
# cross-track contract:
#
#   - Success response: HTTP 200, body EXACTLY {"sent" => true} for EVERY
#     account state (nonexistent / verified / unverified-just-sent /
#     unverified-throttled / internal error / feature-disabled no-op).
#   - The ONLY allowed non-200 is a structurally malformed request
#     (blank/missing login). /api/ paths are CSRF-exempt by design
#     (lib/onetime/middleware/security.rb), so a missing CSRF token is NOT a
#     rejection here. Neither case leaks account existence.
#   - The ONLY observable difference between account states is the SERVER-SIDE
#     audit log (Auth::Logging.log_auth_event) — never the HTTP body/status.
#
# -----------------------------------------------------------------------------
# HARNESS REALITY (read before editing):
#
# This file lives under spec/integration/full/, so spec_helper.rb auto-derives
# the :full_auth_mode metadata tag (see spec/spec_helper.rb
# define_derived_metadata for /integration/full/). That tag triggers, via
# spec/support/full_mode_suite_database.rb:
#   - FullModeSuiteDatabase.setup! (migrates SQLite/PG, stubs Auth::Database
#     connection, boots the app with force: true, rebuilds the Registry)
#   - AuthAccountFactory + the `test_db` helper are mixed in
#   - per-test table cleanup (clean_tables!) after each example
#
# We therefore do NOT call AuthModeHelpers.install_mock / Onetime.boot! /
# Registry.reset! manually in before(:all). The IMPL_SPEC's suggested manual
# boot block does not match how the suite actually wires full mode — the
# directory-derived :full_auth_mode tag does all of it. (Sibling specs that
# use this exact pattern: spec/integration/full/rodauth_spec.rb,
# spec/integration/full/active_sessions_spec.rb.)
#
# verify_account is OFF in RACK_ENV=test boot. The Rodauth verify_account
# feature is enabled at BOOT time only when
# Onetime.auth_config.verify_account_enabled? is true, which the defaults YAML
# forces false under RACK_ENV=test
# (etc/defaults/auth.defaults.yaml: verify_account = ... && ENV['RACK_ENV'] != 'test').
# So in this suite the endpoint takes its `:verify_account_resend_noop` guard
# branch and still returns the uniform 200 — which is exactly what the
# enumeration contract requires.
#
# Consequence for assertions:
#   - The uniform-200 / enumeration-uniformity / malformed-request / CSRF
#     assertions hold UNCONDITIONALLY and are the load-bearing tests here.
#   - The DB-mutation assertions (email_last_sent advanced; verification key
#     not created) and the sent-vs-blocked log differentiation only have teeth
#     when verify_account was actually loaded at boot. We detect that with
#     `verify_account_loaded?` (mirrors the feature-detection + skip pattern in
#     spec/integration/full/env_toggles/magic_links_spec.rb) and `skip` those
#     specific examples otherwise, so the file is green in test-mode CI while
#     still encoding the full contract for environments where the feature is on.
# =============================================================================

require 'spec_helper'

RSpec.describe 'POST /api/account/resend-verification-email', type: :integration do
  include_context 'auth_rack_test'

  ENDPOINT = '/api/account/resend-verification-email'

  # ---------------------------------------------------------------------------
  # Feature detection.
  #
  # The Rodauth verify_account feature (and its internal_request method
  # verify_account_resend) is only present on Auth::Config when the feature was
  # enabled at boot. In RACK_ENV=test it is not. Examples whose assertions
  # require the live rodauth resend flow skip when it is absent.
  # ---------------------------------------------------------------------------
  def verify_account_loaded?
    Onetime.auth_config.respond_to?(:verify_account_enabled?) &&
      Onetime.auth_config.verify_account_enabled? &&
      defined?(Auth::Config) &&
      Auth::Config.respond_to?(:verify_account_resend)
  end

  # Latest email_last_sent for an account's verification key row, or nil.
  def email_last_sent_for(account_id)
    row = test_db[:account_verification_keys].where(id: account_id).first
    row && row[:email_last_sent]
  end

  def verification_key_exists?(account_id)
    test_db[:account_verification_keys].where(id: account_id).count.positive?
  end

  # ===========================================================================
  # SCENARIO 1: Unverified account -> 200 {sent:true}; email_last_sent advanced.
  # ===========================================================================
  describe 'unverified account' do
    it 'returns 200 with the uniform {"sent" => true} body' do
      create_unverified_account(db: test_db, email: 'unverified@example.com')

      post_json ENDPOINT, { login: 'unverified@example.com', locale: 'en' }

      expect(last_response.status).to eq(200)
      expect(json_response).to eq('sent' => true)
    end

    it 'advances account_verification_keys.email_last_sent (when verify_account is enabled)' do
      skip 'verify_account feature not loaded at boot (RACK_ENV=test)' unless verify_account_loaded?

      account = create_unverified_account(db: test_db, email: 'unverified@example.com')
      account_id = account[:id]

      # Backdate the key so a real resend produces a strictly newer timestamp
      # (also moves it outside the resend throttle window).
      old_time = Time.now - 3600
      test_db[:account_verification_keys].where(id: account_id).update(email_last_sent: old_time)

      post_json ENDPOINT, { login: 'unverified@example.com', locale: 'en' }

      expect(last_response.status).to eq(200)
      expect(email_last_sent_for(account_id)).to be > old_time
    end
  end

  # ===========================================================================
  # SCENARIO 2: Verified account -> identical 200 {sent:true}; no key created.
  # ===========================================================================
  describe 'verified account' do
    it 'returns the identical uniform 200 body' do
      create_verified_account(db: test_db, email: 'verified@example.com')

      post_json ENDPOINT, { login: 'verified@example.com', locale: 'en' }

      expect(last_response.status).to eq(200)
      expect(json_response).to eq('sent' => true)
    end

    it 'does not create a verification key for the verified account' do
      account = create_verified_account(db: test_db, email: 'verified@example.com')

      post_json ENDPOINT, { login: 'verified@example.com', locale: 'en' }

      expect(last_response.status).to eq(200)
      expect(verification_key_exists?(account[:id])).to be(false)
    end
  end

  # ===========================================================================
  # SCENARIO 3: Nonexistent login -> identical 200 {sent:true}.
  # ===========================================================================
  describe 'nonexistent login' do
    it 'returns the identical uniform 200 body (no enumeration signal)' do
      post_json ENDPOINT, { login: 'does-not-exist@example.com', locale: 'en' }

      expect(last_response.status).to eq(200)
      expect(json_response).to eq('sent' => true)
    end
  end

  # ===========================================================================
  # SCENARIO 4: Throttle -> two calls in window both 200; 2nd does not advance.
  # ===========================================================================
  describe 'throttling (two calls within the resend window)' do
    it 'returns the identical uniform 200 on both calls' do
      create_unverified_account(db: test_db, email: 'throttle@example.com')

      post_json ENDPOINT, { login: 'throttle@example.com', locale: 'en' }
      first_status = last_response.status
      first_body   = json_response

      post_json ENDPOINT, { login: 'throttle@example.com', locale: 'en' }
      second_status = last_response.status
      second_body   = json_response

      expect(first_status).to eq(200)
      expect(second_status).to eq(200)
      expect(first_body).to eq('sent' => true)
      expect(second_body).to eq(first_body)
    end

    it 'does not advance email_last_sent on the throttled 2nd call (when verify_account is enabled)' do
      skip 'verify_account feature not loaded at boot (RACK_ENV=test)' unless verify_account_loaded?

      account = create_unverified_account(db: test_db, email: 'throttle@example.com')
      account_id = account[:id]

      # First call sends and stamps email_last_sent to "now".
      post_json ENDPOINT, { login: 'throttle@example.com', locale: 'en' }
      after_first = email_last_sent_for(account_id)

      # Second call within verify_account_skip_resend_email_within (default 300s)
      # must be throttled by rodauth — no new send, timestamp unchanged.
      post_json ENDPOINT, { login: 'throttle@example.com', locale: 'en' }
      after_second = email_last_sent_for(account_id)

      expect(last_response.status).to eq(200)
      expect(after_second).to eq(after_first)
    end
  end

  # ===========================================================================
  # SCENARIO 5: ENUMERATION UNIFORMITY across unverified/verified/nonexistent.
  #
  # The single strongest proof: status AND response-shape are byte-identical
  # across all three account states. Each account lives in its own example via
  # fresh setup because per-test cleanup wipes tables between examples; here we
  # create all three within ONE example so they share the same request context.
  # ===========================================================================
  describe 'enumeration uniformity' do
    it 'produces identical status and identical body across all account states' do
      create_unverified_account(db: test_db, email: 'enum-unverified@example.com')
      create_verified_account(db: test_db, email: 'enum-verified@example.com')
      # 'enum-nonexistent@example.com' deliberately not created.

      post_json ENDPOINT, { login: 'enum-unverified@example.com', locale: 'en' }
      unverified_status = last_response.status
      unverified_body   = json_response

      post_json ENDPOINT, { login: 'enum-verified@example.com', locale: 'en' }
      verified_status = last_response.status
      verified_body   = json_response

      post_json ENDPOINT, { login: 'enum-nonexistent@example.com', locale: 'en' }
      nonexistent_status = last_response.status
      nonexistent_body   = json_response

      # Identical HTTP status across all states.
      expect(unverified_status).to eq(200)
      expect(verified_status).to eq(unverified_status)
      expect(nonexistent_status).to eq(unverified_status)

      # Identical body (the frozen {"sent" => true}) across all states.
      expect(unverified_body).to eq('sent' => true)
      expect(verified_body).to eq(unverified_body)
      expect(nonexistent_body).to eq(unverified_body)

      # And explicitly: identical response-key sets (the contract's wording).
      expect(verified_body.keys.sort).to eq(unverified_body.keys.sort)
      expect(nonexistent_body.keys.sort).to eq(unverified_body.keys.sort)
    end
  end

  # ===========================================================================
  # SCENARIO 6: Missing 'login' param -> non-200 (the only allowed non-200).
  # ===========================================================================
  describe "missing 'login' parameter" do
    it 'returns a 4xx client error (not a uniform 200)' do
      post_json ENDPOINT, { locale: 'en' }

      expect(last_response.status).to be >= 400
      expect(last_response.status).to be < 500
    end
  end

  # ===========================================================================
  # SCENARIO 7: Blank 'login' -> non-200 (4xx).
  # ===========================================================================
  describe "blank 'login' parameter" do
    it 'returns a 4xx client error' do
      post_json ENDPOINT, { login: '', locale: 'en' }

      expect(last_response.status).to be >= 400
      expect(last_response.status).to be < 500
    end
  end

  # ===========================================================================
  # SCENARIO 8: CSRF — /api/ endpoints are intentionally CSRF-exempt.
  #
  # The JSON-API CSRF guard exempts ALL /api/ paths
  # (lib/onetime/middleware/security.rb: `return true if
  # req.path.start_with?('/api/')`). Rationale (from that file): anonymous API
  # requests are stateless — with no session cookie there is no CSRF attack
  # vector. This exemption is REQUIRED for this endpoint: an unverified user
  # arrives cold (no session, and possibly no CSRF token) and must still be able
  # to request a resend.
  #
  # So a POST carrying NO CSRF token must NOT be rejected — it returns the same
  # uniform 200 {sent:true}, indistinguishable from any other outcome. (The
  # frontend still sends `shrimp` for consistency with sibling endpoints; it is
  # simply ignored on /api/ paths.)
  # ===========================================================================
  describe 'CSRF exemption (/api/ paths are stateless, no session = no CSRF vector)' do
    it 'accepts a POST with no CSRF token and returns the uniform 200' do
      post ENDPOINT,
        { login: 'csrf-probe@example.com', locale: 'en' }.to_json,
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json'

      expect(last_response.status).to eq(200)
      expect(json_response).to eq('sent' => true)
    end
  end

  # ===========================================================================
  # SCENARIO 9: Audit-log differentiation (server-side ONLY).
  #
  # >>> BACKEND-LOGGING-COUPLED ASSERTION <<<
  # This couples to the backend's CHOSEN logging mechanism:
  #   Auth::Logging.log_auth_event(<event_symbol>, ...)
  # with distinct event symbols per outcome:
  #   :verify_account_resend_sent     (rodauth accepted, email (re)sent)
  #   :verify_account_resend_blocked  (unknown / already-verified / throttled)
  #   :verify_account_resend_error    (infra failure)
  #   :verify_account_resend_noop     (verify_account / full mode disabled)
  # If the backend renames an event or switches to plain OT.info messages,
  # update the captured-event symbols below (one-line tweak).
  #
  # We spy on Auth::Logging.log_auth_event, capture the first positional arg
  # (the event symbol) per request, and assert:
  #   (a) the HTTP bodies are byte-identical across states (no leak), AND
  #   (b) the SERVER-SIDE event symbols DIFFER between the two states.
  #
  # When verify_account is loaded at boot: unverified -> :..._sent vs
  # verified -> :..._blocked (different). When NOT loaded (RACK_ENV=test): both
  # states hit the same :..._noop guard branch, so a sent-vs-blocked difference
  # cannot exist — we skip the "differ" half and still assert that a
  # distinct, greppable resend event is emitted while bodies stay identical.
  # ===========================================================================
  describe 'audit-log differentiation (couples to backend logging choice)' do
    let(:captured_events) { [] }

    before do
      allow(Auth::Logging).to receive(:log_auth_event).and_wrap_original do |orig, event, **kwargs|
        captured_events << event
        orig.call(event, **kwargs)
      end
    end

    it 'emits a resend audit event while keeping the HTTP body uniform' do
      create_unverified_account(db: test_db, email: 'audit-unverified@example.com')

      post_json ENDPOINT, { login: 'audit-unverified@example.com', locale: 'en' }

      expect(last_response.status).to eq(200)
      expect(json_response).to eq('sent' => true)
      # A distinct, greppable server-side signal was emitted for this request.
      resend_events = captured_events.select { |e| e.to_s.start_with?('verify_account_resend_') }
      expect(resend_events).not_to be_empty
    end

    it 'produces DIFFERENT server-side events for unverified vs verified while bodies stay identical' do
      skip 'verify_account feature not loaded at boot (RACK_ENV=test): both states share the noop branch' unless verify_account_loaded?

      create_unverified_account(db: test_db, email: 'audit-unverified@example.com')
      create_verified_account(db: test_db, email: 'audit-verified@example.com')

      captured_events.clear
      post_json ENDPOINT, { login: 'audit-unverified@example.com', locale: 'en' }
      unverified_body   = json_response
      unverified_events = captured_events.dup

      captured_events.clear
      post_json ENDPOINT, { login: 'audit-verified@example.com', locale: 'en' }
      verified_body   = json_response
      verified_events = captured_events.dup

      # HTTP bodies identical (no enumeration leak)...
      expect(verified_body).to eq(unverified_body)
      expect(unverified_body).to eq('sent' => true)

      # ...but the SERVER-SIDE event symbols differ (the distinction lives
      # only in the audit log). The unverified path emits the "sent" event;
      # the verified path emits the "blocked" event.
      expect(unverified_events).to include(:verify_account_resend_sent)
      expect(verified_events).to include(:verify_account_resend_blocked)
      expect(unverified_events).not_to eq(verified_events)
    end
  end
end
