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
    let(:strategy) { instance_double(Onetime::DomainValidation::PassthroughStrategy) }
    let(:delete_result) { { status: 'deleted', message: 'Vhost deleted' } }
    let(:lock) do
      double('Familia::Lock', acquire: 'lock-token', release: true,
        dbkey: 'sender-identity-lock', dbclient: double('Redis', eval: 1))
    end

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
      allow(strategy).to receive(:delete_vhost).and_return(delete_result)
      allow(Onetime::CustomDomain::MailerConfig).to receive(:sender_identity_lock)
        .with('domain123').and_return(lock)

      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@display_domain, 'example.com')
    end

    it 'sets greenlighted flag' do
      logic.send(:process)
      expect(logic.greenlighted).to be true
    end

    it 'destroys the custom domain' do
      expect(custom_domain).to receive(:destroy!)
      logic.send(:process)
    end

    it 'deletes the vhost' do
      expect(strategy).to receive(:delete_vhost).with(custom_domain)
      logic.send(:process)
    end

    context 'domain_context clearing' do
      it 'clears domain_context when it matches the removed domain' do
        expect(session['domain_context']).to eq('example.com')
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

    it 'continues processing despite vhost deletion errors' do
      allow(strategy).to receive(:delete_vhost)
        .and_raise(HTTParty::ResponseError, 'API error')

      expect(OT).to receive(:le).with(/delete_vhost error/)
      expect { logic.send(:process) }.not_to raise_error
    end

    context 'with the sender identity lock' do
      it 'holds it from the teardown through destroy! and releases it' do
        calls = []
        allow(lock).to receive(:acquire) do
          calls << :acquire
          'lock-token'
        end
        allow(strategy).to receive(:delete_vhost) do
          calls << :delete_vhost
          delete_result
        end
        allow(logic).to receive(:delete_sender_domain) { calls << :delete_sender_domain }
        allow(custom_domain).to receive(:destroy!) { calls << :destroy! }
        allow(lock).to receive(:release) { calls << :release }

        logic.send(:process)

        expect(lock).to have_received(:acquire).with(ttl: 60)
        expect(lock).to have_received(:release).with('lock-token')
        expect(calls).to eq([:acquire, :delete_vhost, :delete_sender_domain, :destroy!, :release])
      end

      [:vhost, :sender].each do |phase|
        it "stops after #{phase} teardown on renewal failure, retaining the record and session" do
          if phase == :vhost
            allow(strategy).to receive(:delete_vhost) do
              allow(lock.dbclient).to receive(:eval).and_raise(IOError, 'renewal unavailable')
              delete_result
            end
            expect(logic).not_to receive(:delete_sender_domain)
          else
            allow(logic).to receive(:delete_sender_domain) do
              allow(lock.dbclient).to receive(:eval).and_return(0)
            end
          end

          expect { logic.send(:process) }.to raise_error(OT::FormError) { |ex|
            expect(ex.error_type).to eq(:conflict)
            expect(ex.message).to include('lock lost')
          }
          expect(custom_domain).not_to have_received(:destroy!)
          expect(lock).to have_received(:release).with('lock-token')
          expect(session['domain_context']).to eq('example.com')
        end
      end

      [true, false].each do |matching_context|
        it "reports committed destruction and finalizes the #{matching_context ? 'matching' : 'unrelated'} session on post-destroy lease loss" do
          session['domain_context'] = matching_context ? 'example.com' : 'other.example.com'
          logic.instance_variable_set(:@extid, 'ext-domain123')
          allow(custom_domain).to receive(:destroy!) do
            allow(lock.dbclient).to receive(:eval).and_return(0)
          end

          expect { logic.send(:process) }.to raise_error(OT::FormError) { |ex|
            expect(ex.error_type).to eq(:conflict)
            expect(ex.message).to include('was removed', 'lock lost')
            expect(ex.details).to include(removal_committed: true, lease_lost: true)
          }

          expect(session['domain_context']).to eq(matching_context ? nil : 'other.example.com')
          expect(custom_domain).to have_received(:destroy!).once
          expect(lock).to have_received(:release).with('lock-token')
          expect(OT).to have_received(:info).with('[RemoveDomain] Domain removal committed with lease loss', anything).once
        end
      end

      it 'releases it when destroy! raises' do
        allow(custom_domain).to receive(:destroy!).and_raise(Familia::Problem, 'datastore gone')

        expect { logic.send(:process) }.to raise_error(Familia::Problem)
        expect(lock).to have_received(:release).with('lock-token')
      end

      it 'refuses with a conflict and tears nothing down while another holder has it' do
        allow(lock).to receive(:acquire).and_return(false)

        expect { logic.send(:process) }.to raise_error(OT::FormError) { |ex|
          expect(ex.error_type).to eq(:conflict)
        }
        expect(strategy).not_to have_received(:delete_vhost)
        expect(custom_domain).not_to have_received(:destroy!)
        expect(lock).not_to have_received(:release)
        expect(session['domain_context']).to eq('example.com')
      end
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
