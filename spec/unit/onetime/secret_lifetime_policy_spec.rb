# spec/unit/onetime/secret_lifetime_policy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/secret_lifetime_policy'

RSpec.describe Onetime::SecretLifetimePolicy do
  let(:domain) { instance_double(Onetime::CustomDomain, org_id: 'org-123') }
  let(:organization) { instance_double(Onetime::Organization) }
  let(:billing_config) { instance_double(Onetime::BillingConfig, enabled?: true) }

  before do
    allow(Onetime::BillingConfig).to receive(:instance).and_return(billing_config)
    allow(Onetime::Models::Features::WithEntitlements)
      .to receive(:configured_anonymous_max_ttl).and_return(canonical_ceiling)
    allow(Onetime::Organization).to receive(:free_tier_limits)
      .and_return('secret_lifetime.max' => 1_209_600)
  end

  def config_max
    2_592_000
  end

  def canonical_ceiling
    604_800
  end

  def display_domain
    'secrets.example.com'
  end

  def resolve(strategy:, domain: nil)
    described_class.guest_ceiling(
      config_max: config_max,
      domain_strategy: strategy,
      display_domain: domain,
    )
  end

  it 'uses the configured anonymous ceiling for a canonical-host guest' do
    expect(resolve(strategy: :canonical)).to eq(canonical_ceiling)
  end

  context 'with a custom-domain guest' do
    before do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:load).with('org-123').and_return(organization)
    end

    it 'uses the domain owner free-plan lifetime instead of the canonical ceiling' do
      allow(organization).to receive(:limit_for).with('secret_lifetime').and_return(1_209_600)
      allow(organization).to receive(:can?).with('extended_default_expiration').and_return(false)

      expect(resolve(strategy: :custom, domain: display_domain)).to eq(1_209_600)
    end

    it 'uses the domain owner extended lifetime instead of the canonical ceiling' do
      allow(organization).to receive(:limit_for).with('secret_lifetime').and_return(2_592_000)
      allow(organization).to receive(:can?).with('extended_default_expiration').and_return(true)

      expect(resolve(strategy: :custom, domain: display_domain)).to eq(2_592_000)
    end

    it 'does not grant an extended plan limit without the matching entitlement' do
      allow(organization).to receive(:limit_for).with('secret_lifetime').and_return(2_592_000)
      allow(organization).to receive(:can?).with('extended_default_expiration').and_return(false)

      expect(resolve(strategy: :custom, domain: display_domain)).to eq(1_209_600)
    end

    it 'keeps the configured API maximum as the outer custom-domain bound' do
      allow(organization).to receive(:limit_for).with('secret_lifetime').and_return(7_776_000)
      allow(organization).to receive(:can?).with('extended_default_expiration').and_return(true)

      expect(resolve(strategy: :custom, domain: display_domain)).to eq(config_max)
    end

    it 'uses the configured API maximum when billing is disabled' do
      allow(billing_config).to receive(:enabled?).and_return(false)
      allow(organization).to receive(:limit_for).with('secret_lifetime').and_return(Float::INFINITY)

      expect(resolve(strategy: :custom, domain: display_domain)).to eq(config_max)
    end

    [nil, 0, Float::NAN, -Float::INFINITY].each do |invalid_limit|
      it "falls back to the narrower canonical policy for an invalid plan limit: #{invalid_limit.inspect}" do
        allow(organization).to receive(:limit_for).with('secret_lifetime').and_return(invalid_limit)
        allow(OT).to receive(:le)

        expect(resolve(strategy: :custom, domain: display_domain)).to eq(canonical_ceiling)
      end
    end

    it 'falls back to the narrower canonical policy when the owner is unavailable' do
      allow(Onetime::Organization).to receive(:load).with('org-123').and_return(nil)
      allow(OT).to receive(:le)

      expect(resolve(strategy: :custom, domain: display_domain)).to eq(canonical_ceiling)
    end

    it 'falls back to the narrower canonical policy when tenant lookup raises' do
      allow(Onetime::Organization).to receive(:load).and_raise(StandardError, 'datastore unavailable')
      allow(OT).to receive(:le)

      expect(resolve(strategy: :custom, domain: display_domain)).to eq(canonical_ceiling)
    end
  end
end
