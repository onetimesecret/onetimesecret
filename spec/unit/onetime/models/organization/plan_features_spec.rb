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
end
