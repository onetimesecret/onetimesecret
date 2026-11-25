# spec/unit/onetime/secret_sharing_policy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/secret_lifetime_policy'
require 'onetime/secret_sharing_policy'
require File.join(Onetime::HOME, 'apps', 'web', 'billing', 'errors')

RSpec.describe Onetime::SecretSharingPolicy do
  subject(:policy) { described_class.new(organizations: [organization]) }

  let(:canonical_ceiling) { 604_800 }
  let(:policy_settings) { Onetime::Organization::SharingPolicy::DEFAULT }
  let(:organization) do
    instance_double(Onetime::Organization, objid: 'org-1', sharing_policy: policy_settings)
  end

  before do
    allow(Onetime::SecretLifetimePolicy).to receive(:canonical_guest_ceiling).and_return(canonical_ceiling)
  end

  describe '#max_ttl' do
    it 'uses the canonical guest ceiling for an organization whose plan cannot be resolved' do
      allow(organization).to receive(:limit_for).with('secret_lifetime')
        .and_raise(Billing::PlanCacheMissError.new(plan_id: 'retired_v1'))
      allow(OT).to receive(:le)

      expect(policy.max_ttl).to eq(canonical_ceiling)
      expect(policy.clamp_ttl(2_592_000, ceiling: 2_592_000)).to eq(canonical_ceiling)
      expect(OT).to have_received(:le).with(/Plan lifetime resolution failed/, hash_including(org_id: 'org-1')).twice
    end

    it 'keeps a narrower configured maximum when the plan cannot be resolved' do
      allow(organization).to receive(:sharing_policy).and_return(policy_settings.merge('max_ttl' => 3_600))
      allow(organization).to receive(:limit_for).and_raise(StandardError, 'plan unavailable')
      allow(OT).to receive(:le)

      expect(policy.max_ttl).to eq(3_600)
    end
  end

  context 'with the strictest policy used for an unreadable stored policy' do
    let(:policy_settings) { Onetime::Organization::SharingPolicy::STRICTEST }

    before { allow(organization).to receive(:limit_for).with('secret_lifetime').and_return(2_592_000) }

    it 'refuses recipient email, requires a passphrase and holds the 60-second floor' do
      expect(policy.recipient_allowed?('person@example.com')).to be(false)
      expect(policy.passphrase_required?).to be(true)
      expect(policy.clamp_ttl(604_800, ceiling: 2_592_000)).to eq(60)
      expect(policy.clamp_ttl(1, ceiling: 2_592_000)).to eq(60)
    end
  end
end
