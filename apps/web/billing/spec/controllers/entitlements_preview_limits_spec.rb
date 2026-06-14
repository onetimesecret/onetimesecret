# apps/web/billing/spec/controllers/entitlements_preview_limits_spec.rb
#
# frozen_string_literal: true

# Unit tests for the colonel preview-mode limit resolution in the Entitlements
# controller. These exercise the pure limit-building helpers in isolation
# (no VCR / Stripe / HTTP) by allocating a controller instance and stubbing
# Billing::Plan, mirroring the helper-method pattern in plan_switching_spec.rb.
#
# Regression coverage for: GET /billing/api/entitlements/:extid returning the
# org's actual-plan limits while a colonel is previewing a different plan. The
# entitlements were already preview-aware (entitlements_for_request); limits
# were not, so limit-gated UI reflected the wrong plan.

require_relative '../support/billing_spec_helper'
require_relative '../../application'

RSpec.describe 'Billing::Controllers::Entitlements preview limits' do
  # Allocate without running initialize (which performs workspace self-healing
  # and needs a full request). We only call the pure limit helpers.
  let(:controller) { Billing::Controllers::Entitlements.allocate }

  def stub_session(session)
    req = instance_double('Rack::Request', env: { 'rack.session' => session })
    controller.instance_variable_set(:@req, req)
  end

  describe '#session_preview_planid' do
    it 'returns the symbol-keyed preview plan id' do
      stub_session(entitlement_preview_planid: 'identity_v1')
      expect(controller.send(:session_preview_planid)).to eq('identity_v1')
    end

    it 'treats a blank preview plan id as no preview' do
      stub_session(entitlement_preview_planid: '')
      expect(controller.send(:session_preview_planid)).to be_nil
    end

    it 'returns nil when no preview key is present' do
      stub_session({})
      expect(controller.send(:session_preview_planid)).to be_nil
    end

    it 'returns nil for a non-hash (corrupt/absent) session' do
      stub_session(nil)
      expect(controller.send(:session_preview_planid)).to be_nil
    end
  end

  describe '#preview_limits_hash' do
    it 'maps a Stripe-cached plan, converting infinity to nil' do
      plan = instance_double(
        'Billing::Plan',
        limits_hash: { 'teams.max' => 1, 'custom_domains.max' => Float::INFINITY },
      )
      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('identity_v1')
        .and_return({ plan: plan, config: nil, source: 'stripe' })

      expect(controller.send(:preview_limits_hash, 'identity_v1')).to eq(
        'teams.max' => 1,
        'custom_domains.max' => nil,
      )
    end

    it 'maps a config-only plan, converting unlimited to nil and strings to ints' do
      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('free_v1')
        .and_return(
          {
            plan: nil,
            config: { limits: { 'teams.max' => 'unlimited', 'total_members_per_org.max' => '5' } },
            source: 'local_config',
          },
        )

      expect(controller.send(:preview_limits_hash, 'free_v1')).to eq(
        'teams.max' => nil,
        'total_members_per_org.max' => 5,
      )
    end

    it 'returns an empty hash when the plan cannot be resolved' do
      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('nope')
        .and_return({ plan: nil, config: nil, source: nil })

      expect(controller.send(:preview_limits_hash, 'nope')).to eq({})
    end
  end

  describe '#build_limits_hash with preview active' do
    it 'returns the previewed plan limits and never consults the org' do
      stub_session(entitlement_preview_planid: 'identity_v1')
      plan = instance_double('Billing::Plan', limits_hash: { 'teams.max' => 1 })
      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('identity_v1')
        .and_return({ plan: plan, config: nil, source: 'stripe' })

      # A bare double with no stubbed methods: if the preview short-circuit
      # regressed and the org were consulted, this would raise.
      org = double('Organization')

      expect(controller.send(:build_limits_hash, org)).to eq('teams.max' => 1)
    end
  end
end
