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
      served_as_tenant?: true,
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

  # Source now uses the category-aware `logger` (Onetime::LoggerMethods) instead
  # of the OT.le/OT.ld shims. Stub the instance logger so .debug/.error calls
  # during #process don't hit the real SemanticLogger and can be asserted on.
  let(:app_logger_double) do
    instance_double(SemanticLogger::Logger, info: nil, debug: nil, warn: nil, error: nil)
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(logic).to receive(:logger).and_return(app_logger_double)
    allow(OT).to receive(:now).and_return(Time.now.to_i)
    allow(OT).to receive(:conf).and_return({
      'site' => {},
      'features' => { 'domains' => { 'enabled' => true } },
    })

    allow(logic).to receive(:organization).and_return(organization)
    allow(logic).to receive(:target_organization).and_return(organization)
    allow(logic).to receive(:require_organization!)
    # ADR-012 Stage 4: stub the entitlement gate so existing #process/#success_data tests
    # don't need to wire up a real OrganizationMembership for the mock org.
    # The gate itself is exercised by add_domain_role_gate_try.rb.
    allow(logic).to receive(:require_entitlement_in!)

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

    # The virtual host is created by verification once ownership is verified
    # (Operations::VerifyDomain), not when the domain is added.
    it 'requests no certificate' do
      logic.send(:process)

      expect(strategy).not_to have_received(:request_certificate)
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

  # Under a strategy that checks ownership, a new domain is not served until
  # it is verified (CustomDomain#served_as_tenant?). It does not become the
  # session's domain context, which would make it the share_domain of every
  # secret created next, and secret creation refuses an unserved domain.
  describe 'domain_context for a new domain that is not served (approximated)' do
    let(:new_domain) { Onetime::CustomDomain.new(display_domain: 'example.com', org_id: 'org123') }
    let(:strategy) do
      instance_double(
        Onetime::DomainValidation::ApproximatedStrategy,
        request_certificate: { status: 'requested' },
        proves_ownership?: true,
      )
    end
    let(:session) do
      { 'authenticated' => true, 'csrf' => 'test-csrf-token', 'domain_context' => 'old-domain.com' }
    end

    before do
      allow(OT).to receive(:conf).and_return({
        'site' => {},
        'features' => { 'domains' => { 'enabled' => true, 'validation_strategy' => 'approximated' } },
      })
      allow(Onetime::CustomDomain).to receive(:create!).and_return(new_domain)
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config).and_return(strategy)
      logic.instance_variable_set(:@display_domain, 'example.com')
    end

    it 'leaves the session domain_context as it was and returns none' do
      result = logic.send(:process)

      expect(new_domain.served_as_tenant?).to be(false)
      expect(session['domain_context']).to eq('old-domain.com')
      expect([result[:domain_context], result[:details][:domain_context]]).to eq([nil, nil])
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

    # The client reads it from details (customDomainDetailsSchema).
    it 'returns the domain_context in details too' do
      result_data = logic.send(:process)

      expect(result_data[:details][:domain_context]).to eq('example.com')
    end
  end
end
