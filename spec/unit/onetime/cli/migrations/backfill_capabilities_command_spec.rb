# frozen_string_literal: true

require 'spec_helper'
require 'onetime/cli'

RSpec.describe Onetime::CLI::BackfillCapabilitiesCommand, :aggregate_failures do
  subject(:command) { described_class.new }

  let(:org) { Onetime::Organization.new(display_name: 'Migration fixture').tap(&:save) }
  let(:member) { Onetime::OrganizationMembership.new(role: 'member').tap(&:save) }

  before do
    allow(command).to receive(:boot_application!)
    allow(Onetime::Organization).to receive(:find_by_extid).with(org.extid).and_return(org)
    allow(Onetime::OrganizationMembership).to receive(:active_for_org).with(org).and_return([member])
    allow(org).to receive(:billing_enabled?).and_return(false)
    allow(command).to receive(:puts)
    allow(command).to receive(:warn)
    member.entitlements_grants.add('manage_org')
    member.entitlements_revokes.add('custom_domains')
  end

  after do
    member.destroy_with_index_cleanup!
    org.destroy!
  end

  it 'compares without writing, can be retried, and leaves old readers with their original inputs' do
    command.call(org: org.extid)
    expect(org.dbclient.hget(org.dbkey, 'materialized_plan_features')).to be_nil
    expect(member.dbclient.hget(member.dbkey, 'capability_override:manage_org')).to be_nil
    2.times { command.call(org: org.extid, run: true) }
    expect(member.dbclient.hget(member.dbkey, 'capability_override:manage_org')).to eq('"grant"')
    expect(member.role_capabilities).to eq(['manage_org'])
    expect(member.entitlements_grants.to_a).to eq(['manage_org'])
    expect(member.entitlements_revokes.to_a).to eq(['custom_domains'])
    command.call(org: org.extid, check_rollback: true)
    expect(command).not_to have_received(:warn)
  end

  it 'recognizes an intentional fallback revoke and reports when older readers would restore access' do
    org.update_feature_override('revoke', 'custom_domains')
    command.call(org: org.extid, run: true)
    expect { command.call(org: org.extid, check_rollback: true) }.to raise_error(SystemExit) do |error|
      expect(error.status).to eq(1)
    end
    expect(command).to have_received(:warn).with(/custom_domains/)
    org.update_feature_override('clear', nil)
    command.call(org: org.extid, check_rollback: true)
  end

  it 'reports new membership overrides that an older binary cannot enforce' do
    member.revoke_capability('manage_domains')
    expect { command.call(org: org.extid, check_rollback: true) }.to raise_error(SystemExit)
    expect(command).to have_received(:warn).with(/manage_domains/)
    member.capability_state(action: 'clear')
    command.call(org: org.extid, check_rollback: true)
  end
end
