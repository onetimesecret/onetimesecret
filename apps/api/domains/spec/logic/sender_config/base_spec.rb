# apps/api/domains/spec/logic/sender_config/base_spec.rb
#
# frozen_string_literal: true

# Unit tests for SenderConfig::Base authorization logic.
#
# Issue: #2802 - Per-domain sender configuration API
#
# Tests the authorize_sender_config! method which enforces:
#   1. Feature flag: features.organizations.custom_mail_enabled
#   2. Domain existence via CustomDomain.find_by_extid
#   3. Organization ownership (with colonel bypass)
#   4. Organization entitlement: custom_mail_sender
#
# RUN:
#   pnpm run test:rspec apps/api/domains/spec/logic/sender_config/base_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::SenderConfig::Base do
  # Test through a concrete subclass since Base is abstract
  let(:described_logic_class) { DomainsAPI::Logic::SenderConfig::GetSenderConfig }

  let(:owner) do
    instance_double(
      Onetime::Customer,
      custid: 'owner123',
      objid: 'owner123',
      extid: 'ext-owner123',
      anonymous?: false,
      verified?: true,
    )
  end

  let(:non_owner) do
    instance_double(
      Onetime::Customer,
      custid: 'nonowner123',
      objid: 'nonowner123',
      extid: 'ext-nonowner123',
      anonymous?: false,
      verified?: true,
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org123',
      extid: 'ext-org123',
      display_name: 'Test Org',
    )
  end

  let(:custom_domain) do
    instance_double(
      Onetime::CustomDomain,
      identifier: 'domain123',
      extid: 'ext-domain123',
      display_domain: 'example.com',
      org_id: 'org123',
    )
  end

  let(:session) do
    {
      'authenticated' => true,
      'csrf' => 'test-csrf-token',
    }
  end

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: owner,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:params) { { 'domain_id' => 'ext-domain123' } }
  let(:logic) { described_logic_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(OT).to receive(:now).and_return(Time.now.to_i)
  end

  describe '#authorize_sender_config!' do
    context 'when custom_mail_enabled feature flag is false' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'custom_mail_enabled' => false } },
        })
      end

      it 'raises forbidden error' do
        expect {
          logic.send(:authorize_sender_config!, 'ext-domain123')
        }.to raise_error(Onetime::Forbidden) do |error|
          expect(error.message).to eq('Custom mail sender is not enabled on this instance')
        end
      end
    end

    context 'when custom_mail_enabled feature flag is nil/missing' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => {} },
        })
      end

      it 'raises forbidden error' do
        expect {
          logic.send(:authorize_sender_config!, 'ext-domain123')
        }.to raise_error(Onetime::Forbidden) do |error|
          expect(error.message).to eq('Custom mail sender is not enabled on this instance')
        end
      end
    end

    context 'when features.organizations is completely missing' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => {},
        })
      end

      it 'raises forbidden error' do
        expect {
          logic.send(:authorize_sender_config!, 'ext-domain123')
        }.to raise_error(Onetime::Forbidden) do |error|
          expect(error.message).to eq('Custom mail sender is not enabled on this instance')
        end
      end
    end

    context 'when custom_mail_enabled is true but domain not found' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'custom_mail_enabled' => true } },
        })
        allow(Onetime::CustomDomain).to receive(:find_by_extid).with('nonexistent').and_return(nil)
      end

      it 'raises not_found error' do
        expect {
          logic.send(:authorize_sender_config!, 'nonexistent')
        }.to raise_error(Onetime::RecordNotFound)
      end
    end

    context 'when user is not organization owner' do
      let(:non_owner_strategy_result) do
        double('StrategyResult',
          session: session,
          user: non_owner,
          authenticated?: true,
          metadata: {},
        )
      end
      let(:logic) { described_logic_class.new(non_owner_strategy_result, params) }

      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'custom_mail_enabled' => true } },
        })
        allow(Onetime::CustomDomain).to receive(:find_by_extid)
          .with('ext-domain123').and_return(custom_domain)
        allow(Onetime::Organization).to receive(:load)
          .with('org123').and_return(organization)
        allow(organization).to receive(:owner?).with(non_owner).and_return(false)
        allow(logic).to receive(:cust).and_return(non_owner)
        # Colonel check - user is not a colonel
        allow(non_owner).to receive(:role).and_return('customer')
      end

      it 'raises forbidden error for non-owner' do
        expect {
          logic.send(:authorize_sender_config!, 'ext-domain123')
        }.to raise_error(Onetime::Forbidden) do |error|
          expect(error.message).to include('owner')
        end
      end
    end

    context 'when organization lacks custom_mail_sender entitlement' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'custom_mail_enabled' => true } },
        })
        allow(Onetime::CustomDomain).to receive(:find_by_extid)
          .with('ext-domain123').and_return(custom_domain)
        allow(Onetime::Organization).to receive(:load)
          .with('org123').and_return(organization)
        allow(organization).to receive(:owner?).with(owner).and_return(true)
        allow(organization).to receive(:can?).with('custom_mail_sender').and_return(false)
        allow(logic).to receive(:cust).and_return(owner)
        allow(owner).to receive(:role).and_return('customer')
      end

      it 'raises forbidden error for missing entitlement' do
        expect {
          logic.send(:authorize_sender_config!, 'ext-domain123')
        }.to raise_error(Onetime::Forbidden) do |error|
          expect(error.message).to include('custom_mail_sender')
        end
      end
    end

    context 'when all authorization checks pass' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'custom_mail_enabled' => true } },
        })
        allow(Onetime::CustomDomain).to receive(:find_by_extid)
          .with('ext-domain123').and_return(custom_domain)
        allow(Onetime::Organization).to receive(:load)
          .with('org123').and_return(organization)
        allow(organization).to receive(:owner?).with(owner).and_return(true)
        allow(organization).to receive(:can?).with('custom_mail_sender').and_return(true)
        allow(logic).to receive(:cust).and_return(owner)
        allow(owner).to receive(:role).and_return('customer')
      end

      it 'does not raise an error' do
        expect {
          logic.send(:authorize_sender_config!, 'ext-domain123')
        }.not_to raise_error
      end

      it 'sets @custom_domain' do
        logic.send(:authorize_sender_config!, 'ext-domain123')
        expect(logic.instance_variable_get(:@custom_domain)).to eq(custom_domain)
      end

      it 'sets @organization' do
        logic.send(:authorize_sender_config!, 'ext-domain123')
        expect(logic.instance_variable_get(:@organization)).to eq(organization)
      end
    end

    context 'when user is a colonel (site admin)' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'custom_mail_enabled' => true } },
        })
        allow(Onetime::CustomDomain).to receive(:find_by_extid)
          .with('ext-domain123').and_return(custom_domain)
        allow(Onetime::Organization).to receive(:load)
          .with('org123').and_return(organization)
        # User is NOT the owner but IS a colonel
        allow(organization).to receive(:owner?).with(owner).and_return(false)
        allow(organization).to receive(:can?).with('custom_mail_sender').and_return(true)
        allow(logic).to receive(:cust).and_return(owner)
        allow(owner).to receive(:role).and_return('colonel')
      end

      it 'allows access due to colonel bypass' do
        expect {
          logic.send(:authorize_sender_config!, 'ext-domain123')
        }.not_to raise_error
      end
    end
  end
end
