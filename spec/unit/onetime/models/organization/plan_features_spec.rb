# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/org/entitlement_override'

RSpec.describe Onetime::Organization, :aggregate_failures do # rubocop:disable RSpec/SpecFilePathFormat
  let(:org) { described_class.new(display_name: 'Feature projection').tap(&:save) }
  after { org.destroy! }

  [true, false].each do |billing|
    it "enforces an explicit feature override on an unmaterialized plan with billing #{billing}" do
      allow(org).to receive(:billing_enabled?).and_return(billing)
      org.planid = ''
      org.save
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      allow(Onetime::ColonelAuditEvent).to receive(:record_access)
      apply = lambda do |dry_run|
        Onetime::Operations::Org::EntitlementOverride.new(
          org: org, action: 'revoke', actor: 'operator', entitlement: 'custom_domains',
          kind: 'feature', dry_run: dry_run,
        ).call
      end
      org.entitlements_revokes.add('custom_domains') # Historical fallback override was inactive.
      expect(org.has_feature?('custom_domains')).to be(true)
      expect(apply.call(true).effective).not_to include('custom_domains')
      expect(org.has_feature?('custom_domains')).to be(true)
      expect(apply.call(false).status).to eq(:revoked)
      expect(apply.call(false).status).to eq(:no_change)
      expect(org.has_feature?('custom_domains')).to be(false)
      expect(org.entitlements).to include('custom_domains')
      expect(org.plan_entitlements).not_to include('manage_org')
      org.update_feature_override('clear', nil)
      expect(org.has_feature?('custom_domains')).to be(true)
    end
  end

  it 'repairs the typed billing snapshot after an old writer and keeps rollback inputs intact' do
    allow(org).to receive(:billing_enabled?).and_return(true)
    org.materialize_entitlements_from_config(entitlements: %w[api_access manage_org], limits: {})
    expect(org.plan_entitlements).to eq(['api_access'])
    org.entitlements_grants.add('manage_org')
    org.update_feature_override('grant', 'custom_domains')
    expect(org.entitlements).to include('custom_domains')
    org.update_feature_override('clear', nil)
    expect(org.entitlements_grants.to_a).to contain_exactly('manage_org')
    org.materialized_entitlements.remove_element('api_access')
    expect(org.plan_entitlements).to eq([])
    expect(org.dbclient.hget(org.dbkey, 'materialized_plan_features')).to eq('[]')
    expect { org.update_feature_override('grant', 'manage_org') }.to raise_error(ArgumentError)
  end

  it 'enforces current typed decisions when an older worker publishes its earlier snapshot' do
    allow(org).to receive(:billing_enabled?).and_return(true)
    org.materialize_entitlements_from_config(entitlements: %w[api_access custom_domains], limits: {})
    previous = org.materialized_entitlements.to_a
    org.update_feature_override('revoke', 'custom_domains')
    org.update_feature_override('grant', 'custom_branding')
    org.materialized_entitlements.clear
    previous.each { |name| org.materialized_entitlements.add(name) }
    expect(org.plan_entitlements(persist: false)).to contain_exactly('api_access', 'custom_branding')
    expect(org.entitlements).to contain_exactly('api_access', 'custom_domains')

    org.plan_entitlements
    expect(org.entitlements).to match_array(org.plan_entitlements)
  end

  it 'clears typed provenance even when a legacy clear and revoke run between typed reads' do
    allow(org).to receive(:billing_enabled?).and_return(false)
    org.update_feature_override('revoke', 'custom_domains')
    expect(org.has_feature?('custom_domains')).to be(false)
    org.clear_entitlement_overrides
    org.revoke_entitlement('custom_domains')
    expect(org.has_feature?('custom_domains')).to be(true)

    org.update_feature_override('revoke', 'custom_domains')
    org.grant_entitlement('custom_domains')
    org.revoke_entitlement('custom_domains')
    expect(org.has_feature?('custom_domains')).to be(true)
  end

  it 'uses the persisted materialization timestamp on a stale organization instance' do
    allow(org).to receive(:billing_enabled?).and_return(true)
    org.planid = ''
    org.save
    stale = described_class.load(org.objid)
    allow(stale).to receive(:billing_enabled?).and_return(true)
    org.materialize_entitlements_from_config(entitlements: ['custom_branding'], limits: {})
    expect(stale.plan_entitlements).to eq(['custom_branding'])
    ['null', '""', ''].each do |empty_stamp|
      org.dbclient.hset(org.dbkey, 'materialized_entitlements_at', empty_stamp)
      expect(org.plan_entitlements).to include('api_access')
      expect(org.plan_entitlements).not_to include('custom_branding')
    end
    org.dbclient.hset(org.dbkey, 'materialized_entitlements_at', '1716000000:abc123def456')
    expect(org.plan_entitlements).to eq(['custom_branding'])
    org.dbclient.hset(org.dbkey, 'materialized_entitlements_at', 'false')
    expect { org.has_feature?('api_access') }.to raise_error(/Invalid organization entitlement materialization timestamp/)
  end

  it 'discards a fallback when the stored plan changes during resolution' do
    allow(org).to receive(:billing_enabled?).and_return(true)
    org.planid = 'first'
    org.save
    allow(org).to receive(:unmaterialized_plan_entitlements).with('first') do
      org.dbclient.hset(org.dbkey, 'planid', '"second"')
      ['custom_branding']
    end
    allow(org).to receive(:unmaterialized_plan_entitlements).with('second').and_return(['api_access'])
    expect(org.plan_entitlements).to eq(['api_access'])
  end
end
