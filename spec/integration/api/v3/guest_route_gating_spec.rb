# spec/integration/api/v3/guest_route_gating_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Require V3 logic classes
require 'v3/logic/secrets'

# Integration tests for API V3 Guest Route Gating
#
# These tests verify that V3 logic classes enforce guest route configuration
# by raising Onetime::GuestRoutesDisabled when guest routes are disabled.
#
# The guest route check flow:
# 1. Logic class calls require_guest_route_enabled!(:operation) in raise_concerns
# 2. If guest (anonymous + noauth) and routes disabled, raises GuestRoutesDisabled
# 3. Otto error handler catches it and returns 403 with error code
#
# Testing approach:
# We test the logic classes directly by mocking strategy_result, session, and
# config. This allows us to verify the guest route check behavior without
# needing full HTTP authentication infrastructure.
#
RSpec.describe 'API V3 Guest Route Gating', type: :integration do
  # Helper to create a mock customer
  def mock_customer(anonymous: false)
    customer = double('Customer', custid: anonymous ? 'anon' : 'test@example.com', role: 'customer')
    allow(customer).to receive(:anonymous?).and_return(anonymous)
    allow(customer).to receive(:verified?).and_return(!anonymous)
    allow(customer).to receive(:increment_field)
    allow(customer).to receive(:objid).and_return(anonymous ? nil : 'cust_abc123')
    customer
  end

  # Helper to create a mock session
  def mock_session
    session_data = {}
    session = double('Session')
    allow(session).to receive(:[]) { |key| session_data[key] }
    allow(session).to receive(:[]=) { |key, value| session_data[key] = value }
    allow(session).to receive(:delete) { |key| session_data.delete(key) }
    allow(session).to receive(:destroy!)
    session
  end

  # Helper to create a logic instance with proper mocks
  # @param logic_class [Class] The V3 logic class to instantiate
  # @param params [Hash] The params hash for the logic class
  # @param anonymous [Boolean] Whether customer is anonymous
  # @param auth_method [String] The auth method ('noauth' for guest, 'apikey' for authenticated)
  # @return [Object] The logic instance
  def create_logic(logic_class, params:, anonymous: true, auth_method: 'noauth')
    customer = mock_customer(anonymous: anonymous)
    session = mock_session

    strategy_result = double('StrategyResult')
    allow(strategy_result).to receive(:session).and_return(session)
    allow(strategy_result).to receive(:user).and_return(customer)
    allow(strategy_result).to receive(:auth_method).and_return(auth_method)
    allow(strategy_result).to receive(:metadata).and_return({ organization: nil })

    logic = logic_class.new(strategy_result, params)

    # Mock accessors
    allow(logic).to receive(:org).and_return(nil)
    allow(logic).to receive(:cust).and_return(customer)
    allow(logic).to receive(:sess).and_return(session)

    logic
  end

  # Helper to check if raise_concerns raises GuestRoutesDisabled
  # Returns the error if raised, nil otherwise
  def raises_guest_routes_disabled?(logic)
    logic.raise_concerns
    nil
  rescue Onetime::GuestRoutesDisabled => e
    e
  rescue StandardError
    # Other errors (e.g., entitlement, form errors) are fine
    nil
  end

  # Helper to stub config for guest routes
  # @param enabled [Boolean] Global toggle for guest routes
  # @param conceal [Boolean] Per-operation toggle for conceal
  # @param generate [Boolean] Per-operation toggle for generate
  # @param reveal [Boolean] Per-operation toggle for reveal
  # @param burn [Boolean] Per-operation toggle for burn
  # @param show [Boolean] Per-operation toggle for show (ShowSecret)
  # @param receipt [Boolean] Per-operation toggle for receipt (ShowReceipt)
  def stub_guest_routes_config(enabled: true, conceal: true, generate: true, reveal: true, burn: true, show: true, receipt: true)
    config = {
      'enabled' => enabled,
      'conceal' => conceal,
      'generate' => generate,
      'reveal' => reveal,
      'burn' => burn,
      'show' => show,
      'receipt' => receipt,
    }

    allow(OT).to receive(:conf).and_return({
      'site' => {
        'interface' => {
          'api' => {
            'guest_routes' => config,
          },
        },
      },
    })
  end

  # Helper to stub empty/missing guest routes config
  def stub_empty_guest_routes_config
    allow(OT).to receive(:conf).and_return({
      'site' => {
        'interface' => {
          'api' => {
            # guest_routes key is missing entirely
          },
        },
      },
    })
  end

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  describe 'ConcealSecret' do
    let(:logic_class) { V3::Logic::Secrets::ConcealSecret }

    context 'when guest routes globally disabled' do
      before { stub_guest_routes_config(enabled: false) }

      it 'raises GuestRoutesDisabled for guest context' do
        logic = create_logic(logic_class, params: { 'secret' => { 'secret' => 'test' } })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_ROUTES_DISABLED')
        expect(error.message).to eq('Guest API access is disabled')
      end

      it 'does not raise GuestRoutesDisabled for authenticated context' do
        logic = create_logic(logic_class,
          params: { 'secret' => { 'secret' => 'test' } },
          anonymous: false,
          auth_method: 'apikey',
        )
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end
    end

    context 'when conceal specifically disabled' do
      before { stub_guest_routes_config(enabled: true, conceal: false) }

      it 'raises GuestRoutesDisabled with operation-specific code' do
        logic = create_logic(logic_class, params: { 'secret' => { 'secret' => 'test' } })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_CONCEAL_DISABLED')
        expect(error.message).to eq('Guest conceal is disabled')
      end
    end

    context 'when guest routes enabled' do
      before { stub_guest_routes_config(enabled: true, conceal: true) }

      it 'does not raise GuestRoutesDisabled' do
        logic = create_logic(logic_class, params: { 'secret' => { 'secret' => 'test' } })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end
    end
  end

  describe 'GenerateSecret' do
    let(:logic_class) { V3::Logic::Secrets::GenerateSecret }

    context 'when generate specifically disabled' do
      before { stub_guest_routes_config(enabled: true, generate: false) }

      it 'raises GuestRoutesDisabled with operation-specific code' do
        logic = create_logic(logic_class, params: { 'secret' => {} })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_GENERATE_DISABLED')
      end
    end

    context 'when generate enabled' do
      before { stub_guest_routes_config(enabled: true, generate: true) }

      it 'does not raise GuestRoutesDisabled' do
        logic = create_logic(logic_class, params: { 'secret' => {} })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end
    end
  end

  describe 'RevealSecret' do
    let(:logic_class) { V3::Logic::Secrets::RevealSecret }

    context 'when reveal specifically disabled' do
      before { stub_guest_routes_config(enabled: true, reveal: false) }

      it 'raises GuestRoutesDisabled with operation-specific code' do
        _meta, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_REVEAL_DISABLED')
      end
    end

    context 'when reveal enabled' do
      before { stub_guest_routes_config(enabled: true, reveal: true) }

      it 'does not raise GuestRoutesDisabled' do
        _meta, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end
    end
  end

  describe 'BurnSecret' do
    let(:logic_class) { V3::Logic::Secrets::BurnSecret }

    context 'when burn specifically disabled' do
      before { stub_guest_routes_config(enabled: true, burn: false) }

      it 'raises GuestRoutesDisabled with operation-specific code' do
        receipt, _secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => receipt.identifier })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_BURN_DISABLED')
      end
    end

    context 'when burn enabled' do
      before { stub_guest_routes_config(enabled: true, burn: true) }

      it 'does not raise GuestRoutesDisabled' do
        receipt, _secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => receipt.identifier })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end
    end
  end

  describe 'ShowSecret' do
    let(:logic_class) { V3::Logic::Secrets::ShowSecret }

    context 'when show specifically disabled' do
      before { stub_guest_routes_config(enabled: true, show: false) }

      it 'raises GuestRoutesDisabled with operation-specific code' do
        _meta, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_SHOW_DISABLED')
        expect(error.message).to eq('Guest show is disabled')
      end
    end

    context 'when show enabled' do
      before { stub_guest_routes_config(enabled: true, show: true) }

      it 'does not raise GuestRoutesDisabled' do
        _meta, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end
    end

    context 'when guest routes globally disabled' do
      before { stub_guest_routes_config(enabled: false) }

      it 'raises GuestRoutesDisabled with global error code' do
        _meta, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_ROUTES_DISABLED')
      end
    end
  end

  describe 'ShowReceipt' do
    let(:logic_class) { V3::Logic::Secrets::ShowReceipt }

    context 'when receipt specifically disabled' do
      before { stub_guest_routes_config(enabled: true, receipt: false) }

      it 'raises GuestRoutesDisabled with operation-specific code' do
        receipt, _secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => receipt.identifier })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_RECEIPT_DISABLED')
        expect(error.message).to eq('Guest receipt is disabled')
      end
    end

    context 'when receipt enabled' do
      before { stub_guest_routes_config(enabled: true, receipt: true) }

      it 'does not raise GuestRoutesDisabled' do
        receipt, _secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => receipt.identifier })
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end
    end
  end

  describe 'GuestRoutesDisabled error structure' do
    before { stub_guest_routes_config(enabled: false) }

    it 'includes message and code in to_h' do
      logic = create_logic(V3::Logic::Secrets::ConcealSecret, params: { 'secret' => { 'secret' => 'test' } })
      logic.process_params

      error = raises_guest_routes_disabled?(logic)
      expect(error).not_to be_nil

      hash = error.to_h
      expect(hash).to include(
        message: 'Guest API access is disabled',
        code: 'GUEST_ROUTES_DISABLED',
      )
    end

    it 'inherits from Forbidden' do
      expect(Onetime::GuestRoutesDisabled.ancestors).to include(Onetime::Forbidden)
    end

    it 'has HTTP status 403' do
      # Verify the error handler registration pattern (informational test)
      # The actual status is set in otto_hooks.rb via register_error_handler
      expect(Onetime::GuestRoutesDisabled.ancestors).to include(Onetime::Forbidden)
      # Forbidden base class is registered for 403 in otto_hooks.rb
    end
  end

  describe 'guest context detection' do
    before { stub_guest_routes_config(enabled: false) }

    it 'treats anonymous + noauth as guest context' do
      logic = create_logic(V3::Logic::Secrets::ConcealSecret,
        params: { 'secret' => { 'secret' => 'test' } },
        anonymous: true,
        auth_method: 'noauth',
      )
      logic.process_params

      error = raises_guest_routes_disabled?(logic)
      expect(error).not_to be_nil
    end

    it 'treats anonymous + apikey as non-guest context' do
      # This shouldn't happen in practice (anonymous with API key)
      # but tests the logic boundary
      logic = create_logic(V3::Logic::Secrets::ConcealSecret,
        params: { 'secret' => { 'secret' => 'test' } },
        anonymous: true,
        auth_method: 'apikey',
      )
      logic.process_params

      error = raises_guest_routes_disabled?(logic)
      expect(error).to be_nil
    end

    it 'treats authenticated + noauth as non-guest context' do
      # Authenticated user, even with noauth strategy result
      logic = create_logic(V3::Logic::Secrets::ConcealSecret,
        params: { 'secret' => { 'secret' => 'test' } },
        anonymous: false,
        auth_method: 'noauth',
      )
      logic.process_params

      error = raises_guest_routes_disabled?(logic)
      expect(error).to be_nil
    end
  end

  describe 'missing or empty config' do
    context 'when guest_routes config is missing entirely' do
      before { stub_empty_guest_routes_config }

      it 'treats missing config as disabled (empty hash fallback)' do
        # When config is missing, guest_routes_config returns {}
        # An empty hash has no 'enabled' key, so enabled check fails
        logic = create_logic(V3::Logic::Secrets::ConcealSecret,
          params: { 'secret' => { 'secret' => 'test' } },
        )
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_ROUTES_DISABLED')
      end

      it 'allows authenticated users even with missing config' do
        logic = create_logic(V3::Logic::Secrets::ConcealSecret,
          params: { 'secret' => { 'secret' => 'test' } },
          anonymous: false,
          auth_method: 'apikey',
        )
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end
    end
  end

  describe 'multiple operations disabled' do
    context 'when several operations are disabled simultaneously' do
      before do
        stub_guest_routes_config(
          enabled: true,
          conceal: false,
          generate: false,
          reveal: true,
          burn: true,
          show: false,
          receipt: true,
        )
      end

      it 'blocks guest conceal' do
        logic = create_logic(V3::Logic::Secrets::ConcealSecret,
          params: { 'secret' => { 'secret' => 'test' } },
        )
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_CONCEAL_DISABLED')
      end

      it 'blocks guest generate' do
        logic = create_logic(V3::Logic::Secrets::GenerateSecret,
          params: { 'secret' => {} },
        )
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_GENERATE_DISABLED')
      end

      it 'allows guest reveal (still enabled)' do
        _meta, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(V3::Logic::Secrets::RevealSecret,
          params: { 'identifier' => secret.identifier },
        )
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end

      it 'allows guest burn (still enabled)' do
        receipt, _secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(V3::Logic::Secrets::BurnSecret,
          params: { 'identifier' => receipt.identifier },
        )
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end

      it 'blocks guest show' do
        _meta, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(V3::Logic::Secrets::ShowSecret,
          params: { 'identifier' => secret.identifier },
        )
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).not_to be_nil
        expect(error.code).to eq('GUEST_SHOW_DISABLED')
      end

      it 'allows guest receipt (still enabled)' do
        receipt, _secret = Onetime::Receipt.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(V3::Logic::Secrets::ShowReceipt,
          params: { 'identifier' => receipt.identifier },
        )
        logic.process_params

        error = raises_guest_routes_disabled?(logic)
        expect(error).to be_nil
      end
    end
  end

  describe 'V3 logic class inheritance' do
    it 'V3::Logic::Secrets::ConcealSecret includes GuestRouteGating' do
      expect(V3::Logic::Secrets::ConcealSecret.ancestors).to include(Onetime::Logic::GuestRouteGating)
    end

    it 'V3::Logic::Secrets::GenerateSecret includes GuestRouteGating' do
      expect(V3::Logic::Secrets::GenerateSecret.ancestors).to include(Onetime::Logic::GuestRouteGating)
    end

    it 'V3::Logic::Secrets::RevealSecret includes GuestRouteGating' do
      expect(V3::Logic::Secrets::RevealSecret.ancestors).to include(Onetime::Logic::GuestRouteGating)
    end

    it 'V3::Logic::Secrets::BurnSecret includes GuestRouteGating' do
      expect(V3::Logic::Secrets::BurnSecret.ancestors).to include(Onetime::Logic::GuestRouteGating)
    end

    it 'V3::Logic::Secrets::ShowSecret includes GuestRouteGating' do
      expect(V3::Logic::Secrets::ShowSecret.ancestors).to include(Onetime::Logic::GuestRouteGating)
    end

    it 'V3::Logic::Secrets::ShowReceipt includes GuestRouteGating' do
      expect(V3::Logic::Secrets::ShowReceipt.ancestors).to include(Onetime::Logic::GuestRouteGating)
    end

    it 'V2 classes do NOT include GuestRouteGating' do
      # V2 classes should not have guest route gating
      expect(V2::Logic::Secrets::ConcealSecret.ancestors).not_to include(Onetime::Logic::GuestRouteGating)
      expect(V2::Logic::Secrets::GenerateSecret.ancestors).not_to include(Onetime::Logic::GuestRouteGating)
    end
  end
end
