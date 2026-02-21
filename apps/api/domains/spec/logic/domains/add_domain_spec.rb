# apps/api/domains/spec/logic/domains/add_domain_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::Domains::AddDomain do
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
      safe_dump: { objid: 'org123', display_name: 'Test Org' },
    )
  end

  let(:custom_domain) do
    instance_double(
      Onetime::CustomDomain,
      identifier: 'domain123',
      display_domain: 'example.com',
      domainid: 'domain123',
      vhost: nil,
      updated: nil,
      save: true,
      safe_dump: { display_domain: 'example.com' },
    )
  end

  let(:session) do
    {
      'authenticated' => true,
      'csrf' => 'test-csrf-token',
      'domain_context' => nil,
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

  let(:params) { { 'domain' => 'example.com' } }
  let(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(OT).to receive(:now).and_return(Time.now.to_i)
    allow(OT).to receive(:conf).and_return({
      'site' => {},
      'features' => { 'domains' => { 'enabled' => true } },
    })

    allow(logic).to receive(:organization).and_return(organization)
    allow(logic).to receive(:target_organization).and_return(organization)
    allow(logic).to receive(:require_organization!)

    # Allow vhost= and updated= setters on the custom_domain mock
    allow(custom_domain).to receive(:vhost=)
    allow(custom_domain).to receive(:updated=)

    allow(Onetime::CustomDomain).to receive_messages(
      valid?: true,
      parse: custom_domain,
      load_by_display_domain: nil,
      create!: custom_domain,
    )
    allow(Onetime::DomainValidation::Features).to receive(:safe_dump).and_return({})
  end

  describe '#request_certificate' do
    let(:strategy) { instance_double(Onetime::DomainValidation::ApproximatedStrategy) }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
      # Set instance variables that would normally be set by raise_concerns/process
      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@display_domain, 'example.com')
    end

    context 'with successful certificate request' do
      let(:result) do
        {
          status: 'requested',
          message: 'Certificate requested',
          data: { 'vhost_id' => '123', 'status' => 'PENDING' },
        }
      end

      before do
        allow(strategy).to receive(:request_certificate).and_return(result)
      end

      it 'calls strategy request_certificate' do
        expect(strategy).to receive(:request_certificate).with(custom_domain)
        logic.send(:request_certificate)
      end

      it 'stores vhost data when present' do
        expect(custom_domain).to receive(:vhost=)
          .with(result[:data].to_json)
        logic.send(:request_certificate)
      end

      it 'updates timestamp' do
        expect(custom_domain).to receive(:updated=)
        logic.send(:request_certificate)
      end

      it 'saves custom domain' do
        expect(custom_domain).to receive(:save)
        logic.send(:request_certificate)
      end

      it 'returns result hash' do
        result_returned = logic.send(:request_certificate)
        expect(result_returned).to eq(result)
      end

      it 'logs certificate request' do
        expect(OT).to receive(:info).with(/request_certificate.*requested/)
        logic.send(:request_certificate)
      end
    end

    context 'without data in result' do
      let(:result) { { status: 'external', message: 'Handled externally' } }

      before do
        allow(strategy).to receive(:request_certificate).and_return(result)
      end

      it 'does not store vhost data' do
        expect(custom_domain).not_to receive(:vhost=)
        logic.send(:request_certificate)
      end

      it 'does not save custom domain' do
        expect(custom_domain).not_to receive(:save)
        logic.send(:request_certificate)
      end
    end

    context 'with different strategies' do
      context 'approximated strategy' do
        let(:strategy) { instance_double(Onetime::DomainValidation::ApproximatedStrategy) }
        let(:result) { { status: 'requested', data: { 'vhost' => 'data' } } }

        before do
          allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
            .and_return(strategy)
          allow(strategy).to receive(:request_certificate).and_return(result)
        end

        it 'uses approximated strategy' do
          expect(strategy).to receive(:request_certificate)
          logic.send(:request_certificate)
        end
      end

      context 'passthrough strategy' do
        let(:strategy) { instance_double(Onetime::DomainValidation::PassthroughStrategy) }
        let(:result) { { status: 'external', mode: 'passthrough' } }

        before do
          allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
            .and_return(strategy)
          allow(strategy).to receive(:request_certificate).and_return(result)
        end

        it 'uses passthrough strategy' do
          expect(strategy).to receive(:request_certificate)
          logic.send(:request_certificate)
        end
      end

      context 'caddy on-demand strategy' do
        let(:strategy) { instance_double(Onetime::DomainValidation::CaddyOnDemandStrategy) }
        let(:result) { { status: 'delegated', mode: 'caddy_on_demand' } }

        before do
          allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
            .and_return(strategy)
          allow(strategy).to receive(:request_certificate).and_return(result)
        end

        it 'uses caddy on-demand strategy' do
          expect(strategy).to receive(:request_certificate)
          logic.send(:request_certificate)
        end
      end
    end
  end

  describe '#process' do
    let(:strategy) { instance_double(Onetime::DomainValidation::PassthroughStrategy) }
    let(:result) { { status: 'external' } }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
      allow(strategy).to receive(:request_certificate).and_return(result)
      # Set @display_domain as raise_concerns would do
      logic.instance_variable_set(:@display_domain, 'example.com')
    end

    it 'creates custom domain' do
      expect(Onetime::CustomDomain).to receive(:create!)
        .with('example.com', organization.objid)
      logic.send(:process)
    end

    it 'requests certificate' do
      expect(logic).to receive(:request_certificate)
      logic.send(:process)
    end

    it 'continues processing despite HTTParty errors' do
      allow(strategy).to receive(:request_certificate)
        .and_raise(HTTParty::ResponseError, 'API error')

      expect(OT).to receive(:le).with(/request_certificate error/)
      expect { logic.send(:process) }.not_to raise_error
    end

    it 'continues processing despite standard errors' do
      allow(strategy).to receive(:request_certificate)
        .and_raise(StandardError, 'Unexpected error')

      expect(OT).to receive(:le).with(/Unexpected error/)
      expect { logic.send(:process) }.not_to raise_error
    end

    it 'sets greenlighted flag' do
      logic.send(:process)
      expect(logic.greenlighted).to be true
    end

    it 'sets domain_context in session after creating domain' do
      expect(session['domain_context']).to be_nil
      logic.send(:process)
      expect(session['domain_context']).to eq('example.com')
    end

    it 'sets domain_context to match the display_domain' do
      logic.send(:process)
      expect(session['domain_context']).to eq(custom_domain.display_domain)
    end

    context 'when session already has a domain_context' do
      let(:session) do
        {
          'authenticated' => true,
          'csrf' => 'test-csrf-token',
          'domain_context' => 'old-domain.com',
        }
      end

      it 'overwrites existing domain_context with new domain' do
        expect(session['domain_context']).to eq('old-domain.com')
        logic.send(:process)
        expect(session['domain_context']).to eq('example.com')
      end
    end
  end

  describe '#create_vhost (deprecated)' do
    let(:strategy) { instance_double(Onetime::DomainValidation::PassthroughStrategy) }
    let(:result) { { status: 'external' } }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
      allow(strategy).to receive(:request_certificate).and_return(result)
    end

    it 'delegates to request_certificate' do
      expect(logic).to receive(:request_certificate)
      logic.send(:create_vhost)
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

    it 'includes custom domain safe_dump' do
      expect(custom_domain).to receive(:safe_dump)
      logic.send(:success_data)
    end

    it 'includes cluster details' do
      data = logic.send(:success_data)
      expect(data[:details]).to have_key(:cluster)
    end

    it 'includes domain_context in response' do
      data = logic.send(:success_data)
      expect(data).to have_key(:domain_context)
    end

    it 'returns domain_context matching display_domain' do
      data = logic.send(:success_data)
      expect(data[:domain_context]).to eq('example.com')
    end

    context 'with subdomain' do
      before do
        logic.instance_variable_set(:@display_domain, 'secrets.example.com')
        allow(custom_domain).to receive(:display_domain).and_return('secrets.example.com')
      end

      it 'returns domain_context for subdomain' do
        data = logic.send(:success_data)
        expect(data[:domain_context]).to eq('secrets.example.com')
      end
    end
  end

  describe 'domain_context integration' do
    let(:strategy) { instance_double(Onetime::DomainValidation::PassthroughStrategy) }
    let(:result) { { status: 'external' } }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config).and_return(strategy)
      allow(strategy).to receive(:request_certificate).and_return(result)
      # Set @display_domain as raise_concerns would do
      logic.instance_variable_set(:@display_domain, 'example.com')
    end

    it 'session domain_context matches success_data domain_context after process' do
      result_data = logic.send(:process)

      expect(session['domain_context']).to eq(result_data[:domain_context])
    end

    it 'both session and response contain the same display_domain' do
      logic.send(:process)

      expect(session['domain_context']).to eq('example.com')
      expect(logic.send(:success_data)[:domain_context]).to eq('example.com')
    end
  end
end
