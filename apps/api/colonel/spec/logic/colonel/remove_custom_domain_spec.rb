# apps/api/colonel/spec/logic/colonel/remove_custom_domain_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# The op refuses an apply while provisioning (or another sender identity
# change) holds the domain's sender identity lock. This adapter answers that
# refusal with a conflict, like the customer-facing RemoveDomain.
RSpec.describe ColonelAPI::Logic::Colonel::RemoveCustomDomain do
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

  let(:custom_domain) { instance_double(Onetime::CustomDomain, extid: 'cd_target') }

  let(:op) { double('Operations::Domains::Remove') }

  let(:logic) do
    strategy_result = double(
      'StrategyResult',
      session: {},
      user: colonel,
      auth_method: 'sessionauth',
      metadata: {},
    )
    described_class.new(strategy_result, { 'extid' => 'cd_target', 'dry_run' => 'false' }).tap do |l|
      l.instance_variable_set(:@custom_domain, custom_domain)
    end
  end

  before do
    allow(Onetime::Operations::Domains::Remove).to receive(:new).and_return(op)
  end

  it 'answers SenderIdentityBusy with a conflict' do
    allow(op).to receive(:call).and_raise(
      Onetime::Operations::Domains::Remove::SenderIdentityBusy, 'Another change is in progress. Try again.'
    )

    expect { logic.process }.to raise_error(OT::FormError) { |ex|
      expect(ex.error_type).to eq(:conflict)
      expect(ex.field).to eq(:extid)
      expect(ex.message).to include('in progress')
    }
    expect(Onetime::Operations::Domains::Remove).to have_received(:new)
      .with(hash_including(domain: custom_domain, dry_run: false))
  end
end
