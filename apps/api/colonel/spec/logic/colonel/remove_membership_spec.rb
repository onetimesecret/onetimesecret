# apps/api/colonel/spec/logic/colonel/remove_membership_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# A failed default_org_id cleanup does not undo the removal; the response
# reports it and the log line is a warning (#4860).
RSpec.describe ColonelAPI::Logic::Colonel::RemoveMembership do
  let(:colonel) do
    instance_double(
      Onetime::Customer,
      objid: 'cust_colonel',
      extid: 'ur_colonel',
      role: 'colonel',
      verified?: true,
      anonymous?: false,
    )
  end

  let(:org) { instance_double(Onetime::Organization, extid: 'on_org_ext') }
  let(:member) { instance_double(Onetime::Customer, extid: 'ur_member') }
  let(:op) { double('Operations::Memberships::Remove') }
  let(:app_logger) { double('AppLogger', info: nil, warn: nil) }

  let(:logic) do
    strategy_result = double(
      'StrategyResult',
      session: {},
      user: colonel,
      auth_method: 'sessionauth',
      metadata: {},
    )
    described_class.new(strategy_result, { 'org_id' => 'on_org_ext', 'member_id' => 'ur_member' }).tap do |l|
      l.instance_variable_set(:@org, org)
      l.instance_variable_set(:@customer, member)
    end
  end

  def remove_result(default_org_cleanup:)
    Onetime::Operations::Memberships::Remove::Result.new(
      status: :success,
      org_id: 'on_org_ext',
      customer_id: 'ur_member',
      role: 'member',
      default_org_cleanup: default_org_cleanup,
    )
  end

  before do
    allow(Onetime::Operations::Memberships::Remove).to receive(:new).and_return(op)
    allow(logic).to receive(:app_logger).and_return(app_logger)
  end

  it 'returns a failed cleanup in details and logs at warn' do
    allow(op).to receive(:call).and_return(remove_result(default_org_cleanup: :failed))

    data = logic.process

    expect(data[:record]).to include(member_id: 'ur_member', status: 'success')
    expect(data[:details][:default_org_cleanup]).to eq('failed')
    expect(app_logger).to have_received(:warn)
      .with('[RemoveMembership] Member removal', hash_including(default_org_cleanup: 'failed', status: 'success'))
    expect(app_logger).not_to have_received(:info)
  end

  it 'returns an unchanged cleanup in details and logs at info' do
    allow(op).to receive(:call).and_return(remove_result(default_org_cleanup: :unchanged))

    data = logic.process

    expect(data[:details][:default_org_cleanup]).to eq('unchanged')
    expect(app_logger).to have_received(:info)
      .with('[RemoveMembership] Member removal', hash_including(default_org_cleanup: 'unchanged'))
    expect(app_logger).not_to have_received(:warn)
  end
end
