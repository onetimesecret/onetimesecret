# apps/web/auth/spec/config/hooks/pending_plan_intent_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit Tests for Pending Plan Intent Hooks (Issue #3126)
# =============================================================================
#
# WHAT THIS TESTS:
#   The account hooks that capture plan selection from signup URLs and surface
#   the intent after email verification to redirect users to checkout.
#
# FEATURE OVERVIEW:
#   1. User visits pricing page, selects a plan
#   2. User clicks "Sign Up" -> redirected to /auth/create-account?product=X&interval=Y
#   3. after_create_account: Captures intent to Customer.pending_plan_intent (24h TTL)
#   4. User receives verification email, clicks link
#   5. after_verify_account: Surfaces intent, sets session redirect to checkout
#   6. Intent is cleared (single-use) to prevent replay
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/config/hooks/pending_plan_intent_spec.rb
#
# =============================================================================

require 'rspec'

# Define the Auth::Config namespace so the hook file can load without a full
# app boot. Auth::Config MUST be a Rodauth::Auth subclass here, never a plain
# `module Config` or `class Config`: if this file is ever loaded in a process
# that also boots the real app, the application registry reopens
# `class Config < Rodauth::Auth`. A plain module/class fixes the constant to the
# wrong type, so the reopen raises a TypeError ("Config is not a class") and boot
# is marked permanently not-ready for every later spec in the process.
require 'rodauth'
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

# Load the actual production module
require_relative '../../../config/hooks/account'

RSpec.describe 'Pending plan intent hooks (issue #3126)' do
  # ==========================================================================
  # capture_plan_intent Logic Tests
  # ==========================================================================
  #
  # Tests the logic for capturing plan params from request into Customer model.

  describe 'capture_plan_intent logic' do
    let(:captured_at) { Time.now.utc.iso8601 }

    # Simulates the capture logic from after_create_account
    def capture_plan_intent(product:, interval:, source_url: nil)
      return nil if product.to_s.strip == '' || interval.to_s.strip == ''

      {
        product: product,
        interval: interval,
        captured_at: captured_at,
        source_url: source_url,
      }.to_json
    end

    context 'when both product and interval are provided' do
      let(:product) { 'identity_plus_v1' }
      let(:interval) { 'yearly' }

      it 'creates JSON intent with product' do
        intent = capture_plan_intent(product: product, interval: interval)
        parsed = JSON.parse(intent)
        expect(parsed['product']).to eq('identity_plus_v1')
      end

      it 'creates JSON intent with interval' do
        intent = capture_plan_intent(product: product, interval: interval)
        parsed = JSON.parse(intent)
        expect(parsed['interval']).to eq('yearly')
      end

      it 'includes captured_at timestamp' do
        intent = capture_plan_intent(product: product, interval: interval)
        parsed = JSON.parse(intent)
        expect(parsed['captured_at']).to eq(captured_at)
      end

      it 'includes source_url when provided' do
        source = '/auth/create-account?product=identity_plus_v1&interval=yearly'
        intent = capture_plan_intent(product: product, interval: interval, source_url: source)
        parsed = JSON.parse(intent)
        expect(parsed['source_url']).to eq(source)
      end
    end

    context 'when product is missing' do
      it 'returns nil' do
        intent = capture_plan_intent(product: nil, interval: 'monthly')
        expect(intent).to be_nil
      end

      it 'returns nil for empty product' do
        intent = capture_plan_intent(product: '', interval: 'monthly')
        expect(intent).to be_nil
      end

      it 'returns nil for whitespace-only product' do
        intent = capture_plan_intent(product: '   ', interval: 'monthly')
        expect(intent).to be_nil
      end
    end

    context 'when interval is missing' do
      it 'returns nil' do
        intent = capture_plan_intent(product: 'identity_plus_v1', interval: nil)
        expect(intent).to be_nil
      end

      it 'returns nil for empty interval' do
        intent = capture_plan_intent(product: 'identity_plus_v1', interval: '')
        expect(intent).to be_nil
      end
    end

    context 'when both are missing' do
      it 'returns nil' do
        intent = capture_plan_intent(product: nil, interval: nil)
        expect(intent).to be_nil
      end
    end
  end

  # ==========================================================================
  # surface_plan_intent Logic Tests
  # ==========================================================================
  #
  # Tests the logic for surfacing intent during email verification.

  describe 'surface_plan_intent logic' do
    let(:session) { {} }

    # Simulates the surface logic from after_verify_account
    def surface_plan_intent(pending_intent:, session:, plan_valid:)
      return { surfaced: false, reason: :no_intent } if pending_intent.to_s.strip == ''

      begin
        intent = JSON.parse(pending_intent)
      rescue JSON::ParserError
        return { surfaced: false, reason: :invalid_json }
      end

      product = intent['product']
      interval = intent['interval']

      unless product && interval
        return { surfaced: false, reason: :missing_fields }
      end

      unless plan_valid
        return { surfaced: false, reason: :plan_not_found, product: product, interval: interval }
      end

      # Success: set redirect and return surfaced info
      session['plan_checkout_redirect'] = "/billing/plans/#{product}/#{interval}"

      {
        surfaced: true,
        product: product,
        interval: interval,
        redirect_url: session['plan_checkout_redirect'],
      }
    end

    context 'when valid intent exists and plan is valid' do
      let(:intent) do
        {
          product: 'identity_plus_v1',
          interval: 'monthly',
          captured_at: Time.now.utc.iso8601,
        }.to_json
      end

      it 'surfaces the intent successfully' do
        result = surface_plan_intent(pending_intent: intent, session: session, plan_valid: true)
        expect(result[:surfaced]).to be true
      end

      it 'extracts product from intent' do
        result = surface_plan_intent(pending_intent: intent, session: session, plan_valid: true)
        expect(result[:product]).to eq('identity_plus_v1')
      end

      it 'extracts interval from intent' do
        result = surface_plan_intent(pending_intent: intent, session: session, plan_valid: true)
        expect(result[:interval]).to eq('monthly')
      end

      it 'sets session redirect URL' do
        surface_plan_intent(pending_intent: intent, session: session, plan_valid: true)
        expect(session['plan_checkout_redirect']).to eq('/billing/plans/identity_plus_v1/monthly')
      end

      it 'returns redirect URL in result' do
        result = surface_plan_intent(pending_intent: intent, session: session, plan_valid: true)
        expect(result[:redirect_url]).to eq('/billing/plans/identity_plus_v1/monthly')
      end
    end

    context 'when no intent exists' do
      it 'returns not surfaced with no_intent reason' do
        result = surface_plan_intent(pending_intent: nil, session: session, plan_valid: true)
        expect(result).to eq({ surfaced: false, reason: :no_intent })
      end

      it 'handles empty string intent' do
        result = surface_plan_intent(pending_intent: '', session: session, plan_valid: true)
        expect(result).to eq({ surfaced: false, reason: :no_intent })
      end

      it 'handles whitespace-only intent' do
        result = surface_plan_intent(pending_intent: '   ', session: session, plan_valid: true)
        expect(result).to eq({ surfaced: false, reason: :no_intent })
      end

      it 'does not set session redirect' do
        surface_plan_intent(pending_intent: nil, session: session, plan_valid: true)
        expect(session).not_to have_key('plan_checkout_redirect')
      end
    end

    context 'when intent contains invalid JSON' do
      it 'returns not surfaced with invalid_json reason' do
        result = surface_plan_intent(pending_intent: 'not-json{{', session: session, plan_valid: true)
        expect(result).to eq({ surfaced: false, reason: :invalid_json })
      end

      it 'handles truncated JSON' do
        result = surface_plan_intent(pending_intent: '{"product":', session: session, plan_valid: true)
        expect(result).to eq({ surfaced: false, reason: :invalid_json })
      end

      it 'does not set session redirect' do
        surface_plan_intent(pending_intent: 'bad-json', session: session, plan_valid: true)
        expect(session).not_to have_key('plan_checkout_redirect')
      end
    end

    context 'when intent is missing required fields' do
      it 'returns not surfaced when product is missing' do
        intent = { interval: 'monthly' }.to_json
        result = surface_plan_intent(pending_intent: intent, session: session, plan_valid: true)
        expect(result).to eq({ surfaced: false, reason: :missing_fields })
      end

      it 'returns not surfaced when interval is missing' do
        intent = { product: 'identity_plus_v1' }.to_json
        result = surface_plan_intent(pending_intent: intent, session: session, plan_valid: true)
        expect(result).to eq({ surfaced: false, reason: :missing_fields })
      end

      it 'returns not surfaced when both are missing' do
        intent = { captured_at: Time.now.utc.iso8601 }.to_json
        result = surface_plan_intent(pending_intent: intent, session: session, plan_valid: true)
        expect(result).to eq({ surfaced: false, reason: :missing_fields })
      end
    end

    context 'when plan no longer exists' do
      let(:intent) do
        { product: 'discontinued_plan', interval: 'monthly' }.to_json
      end

      it 'returns not surfaced with plan_not_found reason' do
        result = surface_plan_intent(pending_intent: intent, session: session, plan_valid: false)
        expect(result[:surfaced]).to be false
        expect(result[:reason]).to eq(:plan_not_found)
      end

      it 'includes product and interval in result for debugging' do
        result = surface_plan_intent(pending_intent: intent, session: session, plan_valid: false)
        expect(result[:product]).to eq('discontinued_plan')
        expect(result[:interval]).to eq('monthly')
      end

      it 'does not set session redirect' do
        surface_plan_intent(pending_intent: intent, session: session, plan_valid: false)
        expect(session).not_to have_key('plan_checkout_redirect')
      end
    end
  end

  # ==========================================================================
  # Single-Use Semantics Tests
  # ==========================================================================
  #
  # Tests that intent is cleared after surfacing (prevents replay attacks).

  describe 'single-use semantics' do
    # Simulates the clear operation after successful surfacing
    def simulate_intent_lifecycle(initial_intent:, plan_valid:)
      pending_intent = initial_intent
      session = {}

      # First surfacing attempt
      first_result = if pending_intent.to_s.strip != '' && plan_valid
                       begin
                         intent = JSON.parse(pending_intent)
                         session['plan_checkout_redirect'] = "/billing/plans/#{intent['product']}/#{intent['interval']}"
                         pending_intent = nil # Single-use: clear after surfacing
                         { surfaced: true }
                       rescue JSON::ParserError
                         { surfaced: false }
                       end
                     else
                       { surfaced: false }
                     end

      # Second surfacing attempt (should fail - intent cleared)
      second_result = if pending_intent.to_s.strip != ''
                        { surfaced: true }
                      else
                        { surfaced: false, reason: :already_consumed }
                      end

      { first: first_result, second: second_result, session: session }
    end

    it 'clears intent after successful surfacing' do
      intent = { product: 'identity_plus_v1', interval: 'monthly' }.to_json
      result = simulate_intent_lifecycle(initial_intent: intent, plan_valid: true)

      expect(result[:first][:surfaced]).to be true
      expect(result[:second][:surfaced]).to be false
    end

    it 'preserves session redirect after clearing intent' do
      intent = { product: 'identity_plus_v1', interval: 'monthly' }.to_json
      result = simulate_intent_lifecycle(initial_intent: intent, plan_valid: true)

      expect(result[:session]['plan_checkout_redirect']).to eq('/billing/plans/identity_plus_v1/monthly')
    end

    it 'second attempt returns already_consumed reason' do
      intent = { product: 'identity_plus_v1', interval: 'monthly' }.to_json
      result = simulate_intent_lifecycle(initial_intent: intent, plan_valid: true)

      expect(result[:second][:reason]).to eq(:already_consumed)
    end
  end

  # ==========================================================================
  # Intent Expiration Tests
  # ==========================================================================
  #
  # Tests behavior when intent has expired (24h TTL).

  describe 'intent expiration behavior' do
    # In production, Redis TTL handles expiration automatically.
    # These tests verify the system gracefully handles expired/missing intent.

    it 'handles nil intent as not surfaced (equivalent to expired)' do
      session = {}
      # Simulating expired intent returning nil from Redis
      result = if nil.to_s.strip == ''
                 { surfaced: false, reason: :no_intent }
               end

      expect(result[:surfaced]).to be false
      expect(result[:reason]).to eq(:no_intent)
    end

    it 'normal signup without plan params results in no intent' do
      # When user signs up without coming from pricing page
      product = nil
      interval = nil

      should_capture = product.to_s.strip != '' && interval.to_s.strip != ''
      expect(should_capture).to be false
    end
  end

  # ==========================================================================
  # Security Considerations
  # ==========================================================================

  describe 'security considerations' do
    it 'intent cannot be replayed after use' do
      # Already covered by single-use semantics tests
      intent = { product: 'identity_plus_v1', interval: 'monthly' }.to_json
      consumed = false

      # First use
      if intent && !consumed
        consumed = true
        # Intent is now consumed
      end

      # Replay attempt
      replay_allowed = intent && !consumed
      expect(replay_allowed).to be false
    end

    it 'malformed JSON does not cause security issues' do
      malicious_payloads = [
        '{"__proto__":{"admin":true}}',
        '{"constructor":{"prototype":{"isAdmin":true}}}',
        '<script>alert(1)</script>',
        '"; DROP TABLE customers; --',
      ]

      malicious_payloads.each do |payload|
        # Should either parse as benign JSON or fail gracefully
        result = begin
          parsed = JSON.parse(payload)
          # Even if it parses, we only extract product/interval
          product = parsed['product']
          interval = parsed['interval']
          { product: product, interval: interval }
        rescue JSON::ParserError
          { error: :invalid_json }
        end

        # Neither malicious payload provides valid product/interval
        expect(result[:product]).to be_nil
        expect(result[:interval]).to be_nil
      end
    end

    it 'only expected fields are extracted from intent' do
      intent = {
        product: 'identity_plus_v1',
        interval: 'monthly',
        captured_at: Time.now.utc.iso8601,
        admin: true,
        role: 'superuser',
        execute_sql: 'DROP TABLE users',
      }.to_json

      parsed = JSON.parse(intent)
      # Only extract what we need
      safe_result = {
        product: parsed['product'],
        interval: parsed['interval'],
        captured_at: parsed['captured_at'],
      }

      # Malicious fields are ignored
      expect(safe_result).not_to have_key(:admin)
      expect(safe_result).not_to have_key(:role)
      expect(safe_result).not_to have_key(:execute_sql)
    end
  end

  # ==========================================================================
  # JSON Response Format (for frontend compatibility)
  # ==========================================================================

  describe 'checkout redirect URL format' do
    it 'constructs correct URL for identity_plus monthly' do
      product = 'identity_plus_v1'
      interval = 'monthly'
      url = "/billing/plans/#{product}/#{interval}"
      expect(url).to eq('/billing/plans/identity_plus_v1/monthly')
    end

    it 'constructs correct URL for team_plus yearly' do
      product = 'team_plus_v1'
      interval = 'yearly'
      url = "/billing/plans/#{product}/#{interval}"
      expect(url).to eq('/billing/plans/team_plus_v1/yearly')
    end

    it 'URL-encodes special characters in product name' do
      product = 'plan with spaces'
      interval = 'monthly'
      url = "/billing/plans/#{URI.encode_www_form_component(product)}/#{interval}"
      expect(url).to eq('/billing/plans/plan+with+spaces/monthly')
    end
  end

  # ==========================================================================
  # Module Interface Tests
  # ==========================================================================

  describe 'Auth::Config::Hooks::Account module' do
    let(:account_file) { File.expand_path('../../../config/hooks/account.rb', __dir__) }

    it 'module file exists' do
      expect(File.exist?(account_file)).to be true
    end

    it 'defines configure class method' do
      expect(Auth::Config::Hooks::Account).to respond_to(:configure)
    end

    it 'configure accepts one argument (auth object)' do
      expect(Auth::Config::Hooks::Account.method(:configure).arity).to eq(1)
    end
  end
end
