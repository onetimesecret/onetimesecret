# apps/api/colonel/spec/logic/colonel/domain_adoption_refusal_spec.rb
#
# frozen_string_literal: true

# RepairDomain and TransferDomain adopt an orphaned domain through
# CustomDomain.claim_orphaned_domain, which refuses with a bare
# Onetime::Problem whose message is written for the operator. Both adapters
# turn that into Onetime::FormError (field :extid), which the router answers
# with 422 (Onetime::Application::OttoHooks registers FormError at 422). A
# bare Onetime::Problem has no handler of its own. Subclasses of
# Onetime::Problem keep their own handlers and pass through unchanged.
#
# The ops are stubbed: what is under test is the adapter's translation.

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

RSpec.shared_examples 'a colonel adapter that answers a bare Onetime::Problem with a form error' do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', role: 'colonel',
      verified?: true, anonymous?: false)
  end
  let(:strategy_result) do
    double('StrategyResult', session: {}, user: colonel, auth_method: 'sessionauth', metadata: {})
  end
  let(:custom_domain) do
    double('CustomDomain', extid: 'cd_target', domainid: 'cd_internal', display_domain: 'orphan.example.com',
      org_id: '', exists?: true)
  end
  let(:organization) do
    double('Organization', objid: 'org_internal', org_id: 'org_internal', extid: 'on_target', display_name: 'Target')
  end
  let(:message) { 'Domain orphan.example.com has no organization but is still listed in the domains of organization on_other.' }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Onetime::CustomDomain).to receive(:find_by_extid).with('cd_target').and_return(custom_domain)
    allow(Onetime::Organization).to receive(:load).and_return(nil)
    allow(Onetime::Organization).to receive(:load).with('on_target').and_return(organization)
  end

  def run_with(error)
    op = double(op_class.name)
    allow(op).to receive(:call).and_raise(error)
    allow(op_class).to receive(:new).and_return(op)
    logic = described_class.new(strategy_result, params)
    logic.raise_concerns
    logic.process
  end

  it 'raises a form error on extid with the message of a bare Onetime::Problem' do
    expect { run_with(Onetime::Problem.new(message)) }
      .to raise_error(Onetime::FormError) { |ex| expect([ex.message, ex.field]).to eq([message, :extid]) }
  end

  it 'lets a subclass of Onetime::Problem through unchanged' do
    error = Onetime::TemporarilyUnavailable.new('Try again shortly.', reason: :concurrent_write)

    expect { run_with(error) }.to raise_error(error)
  end
end

RSpec.describe ColonelAPI::Logic::Colonel::RepairDomain do
  let(:op_class) { Onetime::Operations::Domains::Repair }
  let(:params) { { 'extid' => 'cd_target', 'org_id' => 'on_target' } }

  it_behaves_like 'a colonel adapter that answers a bare Onetime::Problem with a form error'
end

RSpec.describe ColonelAPI::Logic::Colonel::TransferDomain do
  let(:op_class) { Onetime::Operations::Domains::Transfer }
  let(:params) { { 'extid' => 'cd_target', 'to_org' => 'on_target' } }

  it_behaves_like 'a colonel adapter that answers a bare Onetime::Problem with a form error'
end
