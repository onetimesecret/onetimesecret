# apps/web/billing/spec/controllers/entitlements_preview_limits_spec.rb
#
# frozen_string_literal: true

# Unit tests for the colonel preview-mode limit resolution in the Entitlements
# controller. These exercise the pure limit-building helpers in isolation
# (no VCR / Stripe / HTTP) by allocating a controller instance and stubbing
# Billing::Plan, mirroring the helper-method pattern in plan_switching_spec.rb.
#
# Regression coverage for: GET /billing/api/entitlements/:extid returning the
# org's actual-plan limits while a colonel is previewing a different plan.
# The preview arrives through the request-scoped Fiber-local (ADR-020) rather
# than the session: build_limits_hash consults Onetime::EntitlementPreview
# because it emits the plan's FULL limits hash via raw storage reads that sit
# below the per-resource limit_for chokepoint.

require_relative '../support/billing_spec_helper'
require_relative '../../application'

RSpec.describe 'Billing::Controllers::Entitlements preview limits' do
  # Allocate without running initialize (which performs workspace self-healing
  # and needs a full request). We only call the pure limit helpers.
  let(:controller) { Billing::Controllers::Entitlements.allocate }

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
      plan = instance_double('Billing::Plan', limits_hash: { 'teams.max' => 1 })
      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('identity_v1')
        .and_return({ plan: plan, config: nil, source: 'stripe' })

      # A bare double with no stubbed methods: if the preview short-circuit
      # regressed and the org were consulted, this would raise.
      org = double('Organization')

      with_entitlement_preview(planid: 'identity_v1') do
        expect(controller.send(:build_limits_hash, org)).to eq('teams.max' => 1)
      end
    end

    it 'falls through to the org when the context lacks a planid' do
      org = double('Organization', planid: '')

      with_entitlement_preview(grants_key: 'session:abc:entitlement_preview_grants') do
        expect(controller.send(:build_limits_hash, org)).to eq({})
      end
    end
  end

  describe '#build_limits_hash without preview' do
    it 'resolves from the org (empty hash when the org has no planid)' do
      org = double('Organization', planid: '')

      expect(controller.send(:build_limits_hash, org)).to eq({})
    end
  end
end
