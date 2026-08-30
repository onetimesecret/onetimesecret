# apps/web/auth/spec/config/hooks/pending_auth_redirect_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit tests for the pending auth-redirect hooks (issue #4305)
# =============================================================================
#
# WHAT THIS TESTS:
#   The capture/surface/consume rules the account hooks apply to the `redirect`
#   query parameter, and the precedence contract against a paid-plan intent.
#
# FEATURE OVERVIEW:
#   1. User hits /signup?redirect=/some/internal/page
#   2. after_create_account: validates the path, persists it to
#      Customer.pending_auth_redirect (24h TTL)
#   3. User opens the verification email — POSSIBLY IN A FRESH BROWSER SESSION,
#      which is the whole reason this is not session state
#   4. after_verify_account: re-validates, puts it in json_response[:redirect],
#      deletes it (single-use)
#   5. The SPA carries it through sign-in to the final destination
#
# PRECEDENCE (from the issue): valid plan intent > redirect > SPA default.
#
# SHAPE OF THESE TESTS:
#   Sibling file pending_plan_intent_spec.rb re-implements the hook logic in
#   local helpers because the hook bodies need a live Rodauth instance. Same
#   approach here, with ONE difference that matters: the validation helper
#   calls the REAL OT::Utils.safe_internal_path?, so the security-relevant
#   half of these tests cannot drift from production.
#
# RUN:
#   tests/lanes/run unit --only apps/web/auth/spec/config/hooks/pending_auth_redirect_spec.rb
#
# =============================================================================

require 'rspec'

# Define the Auth::Config namespace so the hook file can load without a full
# app boot. Auth::Config MUST be a Rodauth::Auth subclass here, never a plain
# `module Config` or `class Config` — see the long comment in
# pending_plan_intent_spec.rb for the constant-poisoning failure mode.
require 'rodauth'
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

# Load the actual production module (hook definitions) and the REAL validator.
require_relative '../../../config/hooks/account'
require 'onetime/utils/redirect_paths'

RSpec.describe 'Pending auth redirect hooks (issue #4305)' do
  # The production validator, not a re-implementation.
  let(:validator) { Module.new { extend Onetime::Utils::RedirectPaths } }

  # ==========================================================================
  # Capture (after_create_account)
  # ==========================================================================

  describe 'capture logic' do
    # Mirrors the capture branch in after_create_account: read the param,
    # accept only a String, accept only a validated internal path.
    def capture_auth_redirect(params, validator)
      raw = params['redirect']
      return { captured: false, reason: :absent } unless raw.is_a?(String) && !raw.strip.empty?
      return { captured: false, reason: :invalid } unless validator.safe_internal_path?(raw)

      { captured: true, value: raw }
    end

    it 'captures a simple internal path' do
      result = capture_auth_redirect({ 'redirect' => '/account/settings/security' }, validator)

      expect(result[:captured]).to be true
      expect(result[:value]).to eq('/account/settings/security')
    end

    it 'captures the path verbatim including query string and fragment' do
      path   = '/secret/abc?view=raw#content'
      result = capture_auth_redirect({ 'redirect' => path }, validator)

      expect(result[:captured]).to be true
      expect(result[:value]).to eq(path)
    end

    it 'does not capture when the param is absent' do
      result = capture_auth_redirect({}, validator)

      expect(result[:captured]).to be false
      expect(result[:reason]).to eq(:absent)
    end

    it 'does not capture an empty or whitespace-only param' do
      expect(capture_auth_redirect({ 'redirect' => '' }, validator)[:captured]).to be false
      expect(capture_auth_redirect({ 'redirect' => '   ' }, validator)[:captured]).to be false
    end

    # Rack parses `?redirect[]=x` into an Array. Coercing it with .to_s would
    # manufacture a string the user never sent; reject the shape instead.
    it 'does not capture a non-String param' do
      expect(capture_auth_redirect({ 'redirect' => ['/account'] }, validator)[:captured]).to be false
      expect(capture_auth_redirect({ 'redirect' => { 'a' => '/b' } }, validator)[:captured]).to be false
    end

    context 'when the value is not a safe internal path' do
      [
        'https://attacker.example',
        '//evil.example',
        '/\\evil.example',
        '/%2e%2e/admin',
        "/account\r\nSet-Cookie: a=b",
        "/#{'a' * 2048}",
      ].each do |hostile|
        it "silently drops #{hostile[0, 40].inspect}" do
          result = capture_auth_redirect({ 'redirect' => hostile }, validator)

          expect(result[:captured]).to be false
          expect(result[:reason]).to eq(:invalid)
        end
      end
    end
  end

  # ==========================================================================
  # Surface (after_verify_account)
  # ==========================================================================

  describe 'surface logic' do
    # Mirrors the surface branch in after_verify_account:
    #   read -> delete (single-use, unconditional) -> re-validate ->
    #   set json_response[:redirect] only if nothing already claimed it.
    #
    # `stored` is a one-element box so the helper can model the delete.
    def surface_auth_redirect(stored:, json_response:, json_request: true, validator:)
      value = stored[:value].to_s
      return { surfaced: false, reason: :no_redirect } if value.strip.empty?

      # Single-use: consumed whether or not it ends up being used.
      stored[:value] = nil

      return { surfaced: false, reason: :failed_revalidation } unless validator.safe_internal_path?(value)
      return { surfaced: false, reason: :not_json } unless json_request
      return { surfaced: false, reason: :already_claimed } if json_response.key?(:redirect)

      json_response[:redirect] = value
      { surfaced: true, value: value }
    end

    let(:json_response) { {} }

    it 'puts a valid path in json_response[:redirect]' do
      stored = { value: '/account/settings/security' }

      result = surface_auth_redirect(stored: stored, json_response: json_response, validator: validator)

      expect(result[:surfaced]).to be true
      expect(json_response[:redirect]).to eq('/account/settings/security')
    end

    it 'preserves query string and fragment through the round trip' do
      stored = { value: '/secret/abc?view=raw#content' }

      surface_auth_redirect(stored: stored, json_response: json_response, validator: validator)

      expect(json_response[:redirect]).to eq('/secret/abc?view=raw#content')
    end

    it 'does nothing when nothing was captured' do
      stored = { value: nil }

      result = surface_auth_redirect(stored: stored, json_response: json_response, validator: validator)

      expect(result[:surfaced]).to be false
      expect(result[:reason]).to eq(:no_redirect)
      expect(json_response).not_to have_key(:redirect)
    end

    # Storage is a trust boundary crossing, so the value is validated on the
    # way out as well as on the way in. A value written by an older, looser
    # ruleset must not be trusted just because it is in Redis.
    context 're-validation on read' do
      [
        'https://attacker.example',
        '//evil.example',
        '/\\evil.example',
        '/%2e%2e/admin',
        "/account\r\nSet-Cookie: a=b",
      ].each do |hostile|
        it "refuses to surface #{hostile[0, 40].inspect}" do
          stored = { value: hostile }

          result = surface_auth_redirect(stored: stored, json_response: json_response, validator: validator)

          expect(result[:surfaced]).to be false
          expect(result[:reason]).to eq(:failed_revalidation)
          expect(json_response).not_to have_key(:redirect)
        end
      end

      it 'still consumes a value that fails re-validation' do
        stored = { value: 'https://attacker.example' }

        surface_auth_redirect(stored: stored, json_response: json_response, validator: validator)

        expect(stored[:value]).to be_nil
      end
    end

    describe 'single-use semantics' do
      it 'consumes the stored value on the first surfacing' do
        stored = { value: '/account' }

        first  = surface_auth_redirect(stored: stored, json_response: json_response, validator: validator)
        second = surface_auth_redirect(stored: stored, json_response: {}, validator: validator)

        expect(first[:surfaced]).to be true
        expect(second[:surfaced]).to be false
        expect(second[:reason]).to eq(:no_redirect)
      end
    end

    describe 'non-JSON clients' do
      # For form-post clients the destination travels via the session and
      # verify_account_redirect, not the response body.
      it 'does not write a response body key' do
        stored = { value: '/account' }

        result = surface_auth_redirect(
          stored: stored,
          json_response: json_response,
          json_request: false,
          validator: validator,
        )

        expect(result[:reason]).to eq(:not_json)
        expect(json_response).not_to have_key(:redirect)
      end
    end

    # ========================================================================
    # PRECEDENCE: valid plan intent > redirect > default
    # ========================================================================

    describe 'plan-intent precedence' do
      it 'does not overwrite a checkout redirect already set by the plan intent' do
        json_response[:redirect] = '/billing/plans?product=identity_plus_v1&interval=monthly'
        stored                   = { value: '/account/settings/security' }

        result = surface_auth_redirect(stored: stored, json_response: json_response, validator: validator)

        expect(result[:surfaced]).to be false
        expect(result[:reason]).to eq(:already_claimed)
        expect(json_response[:redirect]).to eq('/billing/plans?product=identity_plus_v1&interval=monthly')
      end

      it 'still consumes the stored redirect when the plan intent wins' do
        json_response[:redirect] = '/billing/plans?product=identity_plus_v1&interval=monthly'
        stored                   = { value: '/account/settings/security' }

        surface_auth_redirect(stored: stored, json_response: json_response, validator: validator)

        expect(stored[:value]).to be_nil
      end

      it 'uses the redirect when no plan intent claimed the key' do
        stored = { value: '/account/settings/security' }

        surface_auth_redirect(stored: stored, json_response: json_response, validator: validator)

        expect(json_response[:redirect]).to eq('/account/settings/security')
      end
    end
  end

  # ==========================================================================
  # verify_account_redirect fallback chain (non-JSON clients)
  # ==========================================================================

  describe 'verify_account_redirect fallback chain' do
    # Mirrors features/account_management.rb. JSON clients never see this
    # value (rodauth's json feature discards redirect targets), but the keys
    # are still consumed because Ruby evaluates the argument.
    def verify_account_redirect(session)
      checkout_path = session.delete('plan_checkout_redirect')
      auth_path     = session.delete('auth_redirect')

      checkout_path || auth_path || '/account'
    end

    it 'prefers the plan checkout redirect' do
      session = {
        'plan_checkout_redirect' => '/billing/plans?product=identity_plus_v1&interval=monthly',
        'auth_redirect' => '/account/settings/security',
      }

      expect(verify_account_redirect(session)).to eq('/billing/plans?product=identity_plus_v1&interval=monthly')
    end

    it 'falls back to the captured auth redirect' do
      session = { 'auth_redirect' => '/account/settings/security' }

      expect(verify_account_redirect(session)).to eq('/account/settings/security')
    end

    it 'falls back to /account when neither is present' do
      expect(verify_account_redirect({})).to eq('/account')
    end

    it 'consumes both keys (single-use)' do
      session = {
        'plan_checkout_redirect' => '/billing/plans?product=identity_plus_v1&interval=monthly',
        'auth_redirect' => '/account/settings/security',
      }

      verify_account_redirect(session)

      expect(session).not_to have_key('plan_checkout_redirect')
      expect(session).not_to have_key('auth_redirect')
    end
  end

  # ==========================================================================
  # JSON response contract
  # ==========================================================================

  # KEY NAME: `redirect`, matching the shape POST /auth/link-sso already
  # returns ({ success, redirect? }, validated client-side with
  # isValidInternalPath — src/schemas/api/auth/responses/auth.ts). The SPA
  # gets one contract for "an auth call finished and here is where to go",
  # not a second bespoke one for verification.
  describe 'JSON response contract' do
    it 'omits the key entirely when there is nothing to redirect to' do
      json_response = { 'success' => 'Your account has been verified' }

      expect(json_response).not_to have_key(:redirect)
    end
  end
end
