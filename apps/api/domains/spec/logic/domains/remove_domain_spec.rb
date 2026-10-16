# apps/api/domains/spec/logic/domains/remove_domain_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::Domains::RemoveDomain do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      custid: 'cust123',
      objid: 'cust123',
      extid: 'ext-cust123',
      anonymous?: false,
    )
  end

  let(:custom_domain) do
    instance_double(
      Onetime::CustomDomain,
      identifier: 'domain123',
      display_domain: 'example.com',
      domainid: 'domain123',
      destroy!: true,
      mailer_config: nil,
    )
  end

  let(:session) do
    {
      'csrf' => 'test-csrf-token',
      'domain_context' => 'example.com',
    }
  end

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:params) { { 'extid' => 'ext-domain123' } }
  let(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(OT).to receive(:conf).and_return({
      'site' => {},
      'features' => { 'domains' => { 'enabled' => true } },
    })

    allow(logic).to receive(:require_organization!)

    allow(Onetime::CustomDomain).to receive(:find_by_extid)
      .and_return(custom_domain)
    allow(custom_domain).to receive(:owner?).with(customer).and_return(true)
  end

  describe '#process' do
    let(:teardown_result) do
      Onetime::Operations::Domains::Teardown::Result.new(removal_committed: true, lease_error: nil, sender_cleanup: :deleted)
    end
    let(:teardown) { instance_double(Onetime::Operations::Domains::Teardown, call: teardown_result) }
    let(:lease_error) { Onetime::Operations::SenderIdentityLease::Lost.new('Sender identity lock lost') }

    before do
      allow(Onetime::Operations::Domains::Teardown).to receive(:new)
        .with(domain: custom_domain).and_return(teardown)
      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@display_domain, 'example.com')
      logic.instance_variable_set(:@extid, 'ext-domain123')
    end

    it 'sets greenlighted flag' do
      logic.send(:process)
      expect(logic.greenlighted).to be true
    end

    it 'delegates destruction exactly once to shared teardown and returns success data' do
      result = logic.send(:process)

      expect(Onetime::Operations::Domains::Teardown).to have_received(:new).with(domain: custom_domain).once
      expect(teardown).to have_received(:call).once
      expect(custom_domain).not_to have_received(:destroy!)
      expect(result).to include(user_id: customer.objid, record: {}, message: 'Removed example.com')
    end

    context 'domain_context clearing' do
      it 'clears domain_context when it matches the removed domain' do
        logic.send(:process)
        expect(session['domain_context']).to be_nil
      end

      it 'leaves domain_context unchanged when it does not match' do
        session['domain_context'] = 'other-domain.com'
        logic.send(:process)
        expect(session['domain_context']).to eq('other-domain.com')
      end

      it 'handles nil domain_context gracefully' do
        session['domain_context'] = nil
        expect { logic.send(:process) }.not_to raise_error
        expect(session['domain_context']).to be_nil
      end
    end

    it 'maps shared-operation contention to the existing conflict message without clearing the session' do
      allow(teardown).to receive(:call)
        .and_raise(Onetime::Operations::Domains::Teardown::Busy, 'example.com is busy')

      expect { logic.send(:process) }.to raise_error(OT::FormError) { |ex|
        expect(ex.error_type).to eq(:conflict)
        expect(ex.message).to eq("Another change to this domain's sender configuration is in progress. Please try again.")
      }
      expect(session['domain_context']).to eq('example.com')
      expect(custom_domain).not_to have_received(:destroy!)
      expect(OT).not_to have_received(:info).with('[RemoveDomain] Domain removal committed with lease loss', anything)
    end

    it 'maps pre-commit lease loss to a conflict, retaining the session and not logging commitment' do
      allow(teardown).to receive(:call).and_raise(lease_error)

      expect { logic.send(:process) }.to raise_error(OT::FormError) { |ex|
        expect(ex.error_type).to eq(:conflict)
        expect(ex.message).to eq(lease_error.message)
      }
      expect(session['domain_context']).to eq('example.com')
      expect(custom_domain).not_to have_received(:destroy!)
      expect(OT).not_to have_received(:info).with('[RemoveDomain] Domain removal committed with lease loss', anything)
    end

    [true, false].each do |matching_context|
      it "finalizes the #{matching_context ? 'matching' : 'unrelated'} session and logs before reporting committed loss" do
        session['domain_context'] = matching_context ? 'example.com' : 'other.example.com'
        allow(teardown).to receive(:call).and_return(
          Onetime::Operations::Domains::Teardown::Result.new(removal_committed: true, lease_error: lease_error, sender_cleanup: :deleted)
        )
        expected_context = matching_context ? nil : 'other.example.com'
        expect(OT).to receive(:info).with('[RemoveDomain] Domain removal committed with lease loss', anything).once do |_, payload|
          expect(session['domain_context']).to eq(expected_context)
          expect(JSON.parse(payload)).to include(
            'event' => 'domain_removed', 'domain_extid' => 'ext-domain123',
            'domain_display' => 'example.com', 'actor_extid' => customer.extid,
            'removal_committed' => true, 'lease_lost' => true
          )
        end

        expect { logic.send(:process) }.to raise_error(OT::FormError) { |ex|
          expect(ex.error_type).to eq(:conflict)
          expect(ex.message).to include('was removed', 'lock lost')
          expect(ex.details).to include(removal_committed: true, lease_lost: true)
        }
        expect(session['domain_context']).to eq(expected_context)
        expect(teardown).to have_received(:call).once
      end
    end

    it 'propagates unexpected teardown errors unchanged without clearing the session' do
      error = Familia::Problem.new('datastore gone')
      allow(teardown).to receive(:call).and_raise(error)

      expect { logic.send(:process) }.to raise_error { |ex| expect(ex).to equal(error) }
      expect(session['domain_context']).to eq('example.com')
      expect(OT).not_to have_received(:info).with('[RemoveDomain] Domain removal committed with lease loss', anything)
    end
  end

  describe '#success_data' do
    before do
      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@display_domain, 'example.com')
    end

    it 'includes user_id' do
      data = logic.send(:success_data)
      expect(data[:user_id]).to eq(customer.objid)
    end

    it 'includes removal message' do
      data = logic.send(:success_data)
      expect(data[:message]).to eq('Removed example.com')
    end

    it 'returns empty record hash' do
      data = logic.send(:success_data)
      expect(data[:record]).to eq({})
    end
  end
end
