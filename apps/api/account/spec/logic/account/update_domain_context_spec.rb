# apps/api/account/spec/logic/account/update_domain_context_spec.rb
#
# frozen_string_literal: true

# Unit tests for domain context persistence in user sessions
#
# Run with:
#   source .env.test && bundle exec rspec apps/api/account/spec/logic/account/update_domain_context_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'

RSpec.describe AccountAPI::Logic::Account::UpdateDomainContext do
  let(:canonical_domain) { 'onetimesecret.com' }
  let(:custom_domain) { 'secrets.example.com' }

  let(:custom_domain_obj) do
    instance_double(
      Onetime::CustomDomain,
      display_domain: custom_domain,
      ready?: true,
      verified: true,
      resolving: true
    )
  end

  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'test-cust-123',
      extid: 'urtest-cust-123',
      custid: 'test-cust-123',
      anonymous?: false,
      custom_domains_list: [custom_domain_obj]
    )
  end

  let(:session) do
    {
      'csrf' => 'test-csrf-token',
      'domain_context' => nil,
    }
  end

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {}
    )
  end

  let(:params) { { 'domain' => custom_domain } }

  subject(:logic) do
    described_class.new(strategy_result, params)
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:conf).and_return({
      'site' => {},
      'features' => { 'domains' => { 'enabled' => true } },
    })
    allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?) do |host|
      host == canonical_domain
    end
  end

  describe '#process_params' do
    it 'extracts domain from params' do
      expect(logic.new_domain_context).to eq(custom_domain)
    end

    it 'normalizes domain to lowercase' do
      params['domain'] = 'SECRETS.EXAMPLE.COM'
      logic = described_class.new(strategy_result, params)
      expect(logic.new_domain_context).to eq('secrets.example.com')
    end

    it 'strips whitespace from domain' do
      params['domain'] = '  secrets.example.com  '
      logic = described_class.new(strategy_result, params)
      expect(logic.new_domain_context).to eq('secrets.example.com')
    end

    it 'stores old domain context from session' do
      session['domain_context'] = 'old.example.com'
      logic = described_class.new(strategy_result, params)
      expect(logic.old_domain_context).to eq('old.example.com')
    end
  end

  describe '#raise_concerns' do
    context 'when customer is anonymous' do
      let(:customer) do
        instance_double(
          Onetime::Customer,
          objid: 'anon-123',
          anonymous?: true,
          custom_domains_list: []
        )
      end

      it 'raises FormError with unauthorized type' do
        expect { logic.raise_concerns }.to raise_error(OT::FormError, /Authentication required/)
      end
    end

    context 'when domain is missing' do
      let(:params) { { 'domain' => nil } }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Domain is required/)
      end
    end

    context 'when domain is empty' do
      let(:params) { { 'domain' => '' } }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Domain is required/)
      end
    end

    context 'when domain is not owned by user' do
      let(:params) { { 'domain' => 'unknown.example.com' } }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid domain/)
      end
    end

    context 'when domain is the canonical domain' do
      let(:params) { { 'domain' => canonical_domain } }

      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    # Split deployment: site.host serves the app while
    # features.domains.default anchors links. Both are in the canonical
    # set, so both are valid domain contexts.
    context 'when domain is the site host in a split deployment' do
      let(:site_host) { 'app.onetimesecret.com' }
      let(:params) { { 'domain' => site_host } }

      before do
        allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?) do |host|
          [canonical_domain, site_host].include?(host)
        end
      end

      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'when domain is a valid custom domain' do
      let(:params) { { 'domain' => custom_domain } }

      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end

  describe '#process' do
    context 'with valid custom domain' do
      it 'updates session with new domain context' do
        logic.process
        expect(session['domain_context']).to eq(custom_domain)
      end

      it 'returns success data with new domain context' do
        result = logic.process
        expect(result[:domain_context]).to eq(custom_domain)
      end

      it 'returns previous domain context in response' do
        session['domain_context'] = 'old.example.com'
        new_logic = described_class.new(strategy_result, params)
        result = new_logic.process
        expect(result[:previous_domain_context]).to eq('old.example.com')
      end

      it 'marks field as modified' do
        logic.process
        expect(logic.modified?(:domain_context)).to be true
      end

      it 'sets greenlighted to true' do
        logic.process
        expect(logic.greenlighted).to be true
      end
    end

    context 'with canonical domain' do
      let(:params) { { 'domain' => canonical_domain } }

      it 'updates session with canonical domain' do
        logic.process
        expect(session['domain_context']).to eq(canonical_domain)
      end

      it 'returns success data' do
        result = logic.process
        expect(result[:domain_context]).to eq(canonical_domain)
      end
    end

    context 'with invalid domain' do
      let(:params) { { 'domain' => 'invalid.example.com' } }

      it 'returns nil without updating' do
        # Skip raise_concerns which would throw
        result = logic.process
        expect(result).to be_nil
      end

      it 'does not set greenlighted' do
        logic.process
        expect(logic.greenlighted).to be false
      end
    end
  end

  describe '#success_data' do
    it 'returns domain_context' do
      data = logic.success_data
      expect(data[:domain_context]).to eq(custom_domain)
    end

    it 'returns previous_domain_context' do
      session['domain_context'] = 'old.example.com'
      new_logic = described_class.new(strategy_result, params)
      data = new_logic.success_data
      expect(data[:previous_domain_context]).to eq('old.example.com')
    end
  end

  # ==========================================================================
  # AC8 server side (#4063): admission agrees with DomainStrategy's
  # classification.
  #
  # valid_domain? admits any canonical host, and the operator link pool joins
  # the canonical set. Unlike the contexts above, these drive the REAL
  # DomainStrategy through initialize_from_config rather than stubbing
  # canonical_host?, because the point is that the two layers cannot disagree:
  # a context this endpoint accepts must be one the middleware then serves.
  # ==========================================================================
  describe 'operator link pool admission (#4063)' do
    let(:site_host)   { 'app.example.net' }
    let(:link_host)   { 'links.example.net' }
    let(:pool_member) { 'short.example.com' }

    # DomainStrategy keeps its config in class instance variables. Save and
    # restore every one of them so a real initialize_from_config here cannot
    # leak into the rest of the suite.
    around do |example|
      ivars = %i[
        @canonical_domain @domains_enabled @canonical_domains
        @canonical_domains_parsed @anchor_domains_parsed @link_domains
        @domain_context_enabled
      ]
      saved = ivars.to_h do |ivar|
        [ivar, Onetime::Middleware::DomainStrategy.instance_variable_get(ivar)]
      end

      begin
        example.run
      ensure
        saved.each do |ivar, value|
          Onetime::Middleware::DomainStrategy.instance_variable_set(ivar, value)
        end
      end
    end

    before do
      allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).and_call_original
      allow(OT).to receive(:conf).and_return({
        'site' => { 'host' => site_host },
        'features' => {
          'domains' => {
            'enabled' => true,
            'default' => link_host,
            'link_domains' => [pool_member, 'go.acme.com'],
          },
        },
      })
      Onetime::Middleware::DomainStrategy.initialize_from_config(
        OT.conf.dig('features', 'domains'),
      )
    end

    it 'is a precondition that the middleware classifies the pool member canonical' do
      expect(Onetime::Middleware::DomainStrategy.canonical_host?(pool_member)).to be true
    end

    it 'accepts a pool member as a domain context' do
      params['domain'] = pool_member
      logic = described_class.new(strategy_result, params)
      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'accepts any pool member, not just the first' do
      params['domain'] = 'go.acme.com'
      logic = described_class.new(strategy_result, params)
      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'persists the pool member into the session' do
      params['domain'] = pool_member
      logic = described_class.new(strategy_result, params)
      logic.process
      expect(session['domain_context']).to eq(pool_member)
    end

    it 'still accepts both canonical anchors' do
      [link_host, site_host].each do |host|
        params['domain'] = host
        logic = described_class.new(strategy_result, params)
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    it 'rejects a subdomain of a pool member, matching exact classification' do
      params['domain'] = "evil.#{pool_member}"
      logic = described_class.new(strategy_result, params)

      expect(Onetime::Middleware::DomainStrategy.canonical_host?("evil.#{pool_member}")).to be false
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid domain/)
    end

    it 'rejects a host that is neither pooled nor one of the user domains' do
      params['domain'] = 'unrelated.example.org'
      logic = described_class.new(strategy_result, params)
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid domain/)
    end

    # An unparseable pool entry is skipped by the middleware and classifies
    # :invalid, so admission must skip it too — otherwise the endpoint accepts
    # a context the very next request rejects.
    context 'with an unparseable pool entry alongside a valid one' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => { 'host' => site_host },
          'features' => {
            'domains' => {
              'enabled' => true,
              'default' => link_host,
              'link_domains' => [pool_member, '999'],
            },
          },
        })
        Onetime::Middleware::DomainStrategy.initialize_from_config(
          OT.conf.dig('features', 'domains'),
        )
      end

      it 'still accepts the parseable member' do
        params['domain'] = pool_member
        logic = described_class.new(strategy_result, params)
        expect { logic.raise_concerns }.not_to raise_error
      end

      it 'rejects the unparseable entry' do
        params['domain'] = '999'
        logic = described_class.new(strategy_result, params)

        expect(Onetime::Middleware::DomainStrategy.canonical_host?('999')).to be false
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid domain/)
      end
    end
  end

  describe 'domain validation' do
    context 'when domains feature is disabled' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {},
          'features' => { 'domains' => { 'enabled' => false } },
        })
      end

      it 'still allows canonical domain' do
        params['domain'] = canonical_domain
        logic = described_class.new(strategy_result, params)
        expect { logic.raise_concerns }.not_to raise_error
      end

      it 'rejects custom domains' do
        params['domain'] = custom_domain
        logic = described_class.new(strategy_result, params)
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid domain/)
      end
    end
  end
end
