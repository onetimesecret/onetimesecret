# apps/api/colonel/spec/logic/colonel/remove_membership_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# A failed default_org_id cleanup does not undo the removal; the response
# reports it and the log line is a warning (#4860).
#
# Each example runs raise_concerns before process, as the router does, so
# the resolvers, the elevation and confirmation guard, and the destructive
# budget all run. The limiter call is spied: the colonel unit suite runs
# without Redis (see destructive_budget_order_spec.rb).
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

  let(:org) { instance_double(Onetime::Organization, extid: 'on_org_ext', exists?: true) }
  let(:member) { instance_double(Onetime::Customer, extid: 'ur_member', email: 'member@example.com') }
  let(:op) { double('Operations::Memberships::Remove') }
  let(:app_logger) { double('AppLogger', info: nil, warn: nil) }
  let(:logic) { build_logic }

  def build_logic(confirm_token: 'member@example.com')
    strategy_result = double(
      'StrategyResult',
      session: elevated_session('ur_colonel'),
      user: colonel,
      auth_method: 'sessionauth',
      metadata: { confirm_token: confirm_token },
    )
    described_class.new(strategy_result, { 'org_id' => 'on_org_ext', 'member_id' => 'ur_member' }).tap do |l|
      allow(l).to receive(:enforce_colonel_destructive_limit!)
      allow(l).to receive(:app_logger).and_return(app_logger)
    end
  end

  def run_request(logic)
    logic.raise_concerns
    logic.process
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
    stub_colonel_elevation(enabled: true, window: 600)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(org)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).with('ur_member').and_return(member)
    allow(Onetime::Operations::Memberships::Remove).to receive(:new).and_return(op)
  end

  it 'returns a failed cleanup in details and logs at warn' do
    allow(op).to receive(:call).and_return(remove_result(default_org_cleanup: :failed))

    data = run_request(logic)

    expect(Onetime::Operations::Memberships::Remove).to have_received(:new)
      .with(hash_including(org: org, customer: member, actor: 'ur_colonel'))
    expect(logic).to have_received(:enforce_colonel_destructive_limit!).with('ur_colonel')
    expect(data[:record]).to include(member_id: 'ur_member', status: 'success')
    expect(data[:details][:default_org_cleanup]).to eq('failed')
    expect(app_logger).to have_received(:warn)
      .with('[RemoveMembership] Member removal', hash_including(default_org_cleanup: 'failed', status: 'success'))
    expect(app_logger).not_to have_received(:info)
  end

  it 'returns an unchanged cleanup in details and logs at info' do
    allow(op).to receive(:call).and_return(remove_result(default_org_cleanup: :unchanged))

    data = run_request(logic)

    expect(data[:details][:default_org_cleanup]).to eq('unchanged')
    expect(app_logger).to have_received(:info)
      .with('[RemoveMembership] Member removal', hash_including(default_org_cleanup: 'unchanged'))
    expect(app_logger).not_to have_received(:warn)
  end

  it 'refuses a request without the member email confirmation before the op runs' do
    logic = build_logic(confirm_token: nil)

    expect { run_request(logic) }.to raise_error(Onetime::ConfirmationRequired)
    expect(Onetime::Operations::Memberships::Remove).not_to have_received(:new)
    expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
  end
end
