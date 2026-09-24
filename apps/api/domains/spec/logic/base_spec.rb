# apps/api/domains/spec/logic/base_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::Base do
  # Pins the contract of #resolve_target_organization:
  #   - Blank/nil/unknown identifiers return nil (Familia finders return nil
  #     on empty ids; they do not raise Familia::NoIdentifier here).
  #   - A found org that the caller is not a member of returns nil.
  #   - A datastore error propagates.
  #
  # Exercised through AddDomain because Base is abstract and its constructor
  # only runs on a concrete Logic subclass.

  let(:customer) do
    instance_double(
      Onetime::Customer,
      custid: 'cust123',
      objid: 'cust123',
      extid: 'ext-cust123',
      anonymous?: false,
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org123',
      display_name: 'Test Org',
    )
  end

  let(:strategy_result) do
    double('StrategyResult',
      session: {},
      user: customer,
      authenticated?: true,
      metadata: {})
  end

  let(:logic) { DomainsAPI::Logic::Domains::AddDomain.new(strategy_result, {}) }

  before do
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(OT).to receive(:info)
    allow(OT).to receive(:conf).and_return({
      'site' => {},
      'features' => { 'domains' => { 'enabled' => true } },
    })
  end

  describe '#resolve_target_organization' do
    context 'when org_id is blank' do
      it 'returns nil for nil without raising' do
        # Callers gate blank input, but the resolver's docstring contract is
        # nil-on-blank. Familia finders return nil for empty ids (they do not
        # raise Familia::NoIdentifier — that's reserved for exists?/destroy!/
        # persistence). Pin the contract so a future finder change is caught.
        expect(Onetime::Organization).to receive(:load).with(nil).and_return(nil)
        expect(Onetime::Organization).to receive(:find_by_extid).with(nil).and_return(nil)

        expect(logic.send(:resolve_target_organization, nil)).to be_nil
      end

      it 'returns nil for the empty string without raising' do
        expect(Onetime::Organization).to receive(:load).with('').and_return(nil)
        expect(Onetime::Organization).to receive(:find_by_extid).with('').and_return(nil)

        expect(logic.send(:resolve_target_organization, '')).to be_nil
      end
    end

    context 'when neither lookup finds an organization' do
      it 'returns nil' do
        expect(Onetime::Organization).to receive(:load).with('unknown').and_return(nil)
        expect(Onetime::Organization).to receive(:find_by_extid).with('unknown').and_return(nil)

        expect(logic.send(:resolve_target_organization, 'unknown')).to be_nil
      end
    end

    context 'when the objid lookup finds an organization the caller belongs to' do
      it 'returns the organization' do
        expect(Onetime::Organization).to receive(:load).with('org123').and_return(organization)
        expect(Onetime::Organization).not_to receive(:find_by_extid)
        expect(organization).to receive(:member?).with(customer).and_return(true)

        expect(logic.send(:resolve_target_organization, 'org123')).to eq(organization)
      end
    end

    context 'when the extid lookup finds an organization the caller belongs to' do
      it 'returns the organization' do
        expect(Onetime::Organization).to receive(:load).with('on-abc').and_return(nil)
        expect(Onetime::Organization).to receive(:find_by_extid).with('on-abc').and_return(organization)
        expect(organization).to receive(:member?).with(customer).and_return(true)

        expect(logic.send(:resolve_target_organization, 'on-abc')).to eq(organization)
      end
    end

    context 'when the caller is not a member of the found organization' do
      it 'returns nil' do
        expect(Onetime::Organization).to receive(:load).with('org123').and_return(organization)
        expect(organization).to receive(:member?).with(customer).and_return(false)

        expect(logic.send(:resolve_target_organization, 'org123')).to be_nil
      end
    end

    context 'when the datastore raises' do
      it 'propagates the error rather than swallowing it as not-found' do
        # Docstring contract: "a datastore error propagates as it would
        # anywhere else in a logic class, so a caller that gates authorization
        # on the answer never sees an outage as 'not found'."
        expect(Onetime::Organization).to receive(:load).with('org123').and_raise(Redis::CannotConnectError)

        expect { logic.send(:resolve_target_organization, 'org123') }
          .to raise_error(Redis::CannotConnectError)
      end
    end
  end
end
