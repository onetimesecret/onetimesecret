# spec/integration/full/routes/update_locale_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Regression contract for POST /api/account/update-locale (auth=noauth). #3516
#
# These tests make REAL HTTP requests to the mounted Rack application via
# Rack::Test (the `auth_rack_test` shared context), reproducing the exact
# cold-anonymous scenario from the bug report:
#
#   curl '/api/account/update-locale' -H 'accept: application/json' \
#        --data-raw '{"locale":"..."}'      # no session, no CSRF token
#
# The endpoint is deliberately noauth: anonymous callers may set their
# session locale. The bug was that UpdateLocale#process_params read
# `cust.locale` unconditionally, so any anonymous request raised
# NoMethodError (a 500) before validation ever ran — even though process_params
# executes for EVERY request via Onetime::Logic::Base#initialize.
#
# The load-bearing invariant these tests pin:
#   an anonymous request MUST NOT produce a 500.
# A valid locale returns 200; an unsupported locale returns a 4xx form error.
# Both outcomes prove the nil-cust crash is gone.
#
# Why an integration (not just unit) spec: only the full stack exercises the
# real param path — Otto's indifferent params over a string-keyed JSON body —
# and the auth=noauth route wiring that hands the logic a nil customer. A
# mock-based unit spec cannot catch a regression in that wiring.
#
# HARNESS NOTE: this file lives under spec/integration/full/, so spec_helper.rb
# auto-derives the :full_auth_mode tag and full_mode_suite_database.rb boots the
# app + mounts the Registry (same pattern as the sibling
# resend_verification_email_spec.rb). update-locale itself needs neither rodauth
# nor the auth DB; it simply rides the already-booted full-mode app.
# =============================================================================

require 'spec_helper'

RSpec.describe 'POST /api/account/update-locale', type: :integration do
  include_context 'auth_rack_test'

  # The endpoint path is inlined rather than held in a describe-block constant:
  # constants assigned inside an RSpec describe block leak to Object scope, so a
  # shared name (e.g. ENDPOINT) collides with sibling route specs once the suite
  # loads them together. A local helper keeps this spec self-contained.
  #
  # Cold anonymous request: no session cookie, no CSRF token — exactly the bug
  # report's curl. /api/ paths are CSRF-exempt (lib/onetime/middleware/
  # security.rb), so this is a well-formed request, not a rejected one.
  def post_locale(body)
    post '/api/account/update-locale',
      body.to_json,
      'CONTENT_TYPE' => 'application/json',
      'HTTP_ACCEPT' => 'application/json'
  end

  describe 'anonymous request with a supported locale' do
    it 'returns 200 (not the 500 from #3516)' do
      post_locale(locale: 'fr_CA')

      expect(last_response.status).to eq(200)
    end

    it 'echoes the new locale in the response body' do
      post_locale(locale: 'fr_CA')

      expect(json_response['new_locale']).to eq('fr_CA')
    end

    it 'reports no previous locale for a fresh anonymous session' do
      post_locale(locale: 'fr_CA')

      # Anonymous callers have no Customer record; the "old" locale is read
      # from the session, which is empty on a cold request.
      expect(json_response).to have_key('old_locale')
      expect(json_response['old_locale']).to be_nil
    end
  end

  describe 'anonymous request with an unsupported locale' do
    it 'returns a 4xx form error, never a 500' do
      # The original bug crashed BEFORE validation, so even an invalid locale
      # 500'd. It must now be rejected cleanly by the locale allowlist.
      post_locale(locale: 'nl') # not in the test config's supported locales

      expect(last_response.status).to eq(422)
      expect(last_response.status).to be < 500
    end
  end

  describe 'anonymous request with a malformed body' do
    it 'does not 500 when locale is missing' do
      post_locale(some_other_field: 'x')

      expect(last_response.status).to be < 500
    end
  end
end
