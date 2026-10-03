# frozen_string_literal: true

# H-02 reproduction pins, NOT assertions that the bypass is intended policy.
# A warm cache selects an org that cold domain selection rejects. Keep these
# controls until cache/session-selection policy is resolved; changing only the
# host source cannot make a cache hit execute the scope gate.
require 'spec_helper'
require 'middleware/detect_host'
require 'onetime/application/organization_loader'
require 'onetime/custom_domain_resolution'
require 'onetime/middleware/public_host_rewrite'
require_relative '../../apps/api/v2/application'

RSpec.describe Onetime::Application::OrganizationLoader do
  let(:loader) { Class.new { include Onetime::Application::OrganizationLoader }.new }
  let(:customer) do
    double('customer', objid: 'customer_scoped', custid: 'scoped@example.com',
      extid: 'customer_external', anonymous?: false, default_org_id: '',
      organization_instances: [organization])
  end
  let(:organization) do
    double('organization', objid: 'org_scoped', extid: 'org_external',
      display_name: 'Scoped organization', archived?: false, is_default: false,
      receipts: receipt_index, planid: 'test_plan')
  end
  let(:allowed_domain) { double('allowed domain', objid: 'domain_allowed', primary_organization: organization) }
  let(:denied_domain) { double('denied domain', objid: 'domain_denied', primary_organization: organization) }
  # Exercise the real scope predicate; only storage and entitlement grants are
  # stubbed. The audit grant is an explicit precondition, not a member default.
  let(:membership) { Onetime::OrganizationMembership.new(domain_scope_id: allowed_domain.objid) }
  let(:receipt_index) { double('org receipt index', rangebyscore: ['sibling_receipt']) }
  let(:foreign_receipt) do
    double('sibling-domain receipt', owner?: false, safe_dump: {
      identifier: 'receipt_bearer', key: 'receipt_bearer', shortid: 'short123',
      secret_identifier: 'secret_bearer', updated: 1_800_000_000,
      is_destroyed: false, state: 'new', memo: 'Sibling-domain metadata',
    })
  end
  let(:session) { {} }
  let(:cache_key) { "org_context:#{customer.objid}" }

  before do
    allow(Familia).to receive(:now).and_return(1_800_000_000)
    allow(Onetime::Organization).to receive(:load).with(organization.objid).and_return(organization)
    allow(organization).to receive(:member?).with(customer).and_return(true)
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .with(organization.objid, customer.objid).and_return(membership)
    allow(membership).to receive(:active?).and_return(true)
    allow(membership).to receive(:can?) { |entitlement| %w[api_access audit_logs].include?(entitlement) }
    allow(Onetime::CustomDomain).to receive(:from_display_domain).with('origin.example.com').and_return(nil)
    allow(Onetime::Receipt).to receive(:load_multi).with(['sibling_receipt']).and_return([foreign_receipt])
    conf = OT.conf.to_h.merge('features' => { 'organizations' => { 'audit_logs_enabled' => true } })
    allow(OT).to receive(:conf).and_return(conf)
  end

  def request_env(domain, hostname, rewrite:, header:)
    env = {
      'HTTP_HOST' => 'origin.example.com', 'SERVER_NAME' => 'origin.example.com',
      'SERVER_PORT' => '443', 'rack.url_scheme' => 'https',
      Rack::DetectHost.result_field_name => hostname,
      'onetime.display_domain' => hostname, 'onetime.domain_strategy' => :custom,
      Onetime::CustomDomainResolution::ENV_KEY => Onetime::CustomDomainResolution.found(hostname, domain),
    }
    env['HTTP_O_ORGANIZATION_ID'] = organization.objid if header
    allow(Onetime::Middleware::PublicHostRewrite).to receive(:enabled?).and_return(rewrite)
    Onetime::Middleware::PublicHostRewrite.new(->(_) { [200, {}, []] }).call(env)
    expect(env['HTTP_HOST']).to eq(rewrite ? hostname : 'origin.example.com')
    env
  end

  def load_context(domain, hostname, rewrite:, header:)
    loader.load_organization_context(customer, session,
      request_env(domain, hostname, rewrite: rewrite, header: header))
  end

  def receipt_logic(context)
    result = double('strategy result', user: customer, session: session,
      metadata: { organization_context: context, domain_strategy: :custom,
        display_domain: 'denied.example.com', custom_domain_id: denied_domain.objid })
    V2::Logic::Secrets::ListReceipts.new(result, { 'scope' => 'org' })
  end

  [false, true].each do |rewrite|
    [false, true].each do |header|
      context "rewrite=#{rewrite}, #{header ? 'matching header' : 'ordinary cache'}" do
        it 'pins cold selection: rewrite exposes the sibling-domain denial' do
          expect(membership.can_access_domain?(denied_domain)).to be(false)
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to eq(rewrite ? nil : organization)
          expect(session.key?(cache_key)).to be(!rewrite)
        end

        it 'reproduces H-02: warm IDs skip scope and reach the shared receipt index' do
          warm = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(warm[:organization]).to eq(organization)
          expect(session[cache_key][:expires_at]).to eq(Familia.now + described_class::CACHE_TTL)
          expect(membership).not_to receive(:can_access_domain?)
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to eq(organization)
          logic = receipt_logic(context)
          expect(logic.auth_org).to eq(organization)
          expect(logic.auth_membership).to eq(membership)
          logic.raise_concerns # Real api_access / audit_logs / active-membership gates.
          expect(receipt_index).to receive(:rangebyscore).with(logic.since, logic.now).and_return(['sibling_receipt'])
          response = logic.process
          expect(response['count']).to eq(1)
          expect(response['records'].first).to include(memo: 'Sibling-domain metadata',
            identifier: 'short123', key: 'short123', secret_identifier: nil)
        end

        it 'pins expiry: the rewritten cold path denies the previously cached org' do
          load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          session[cache_key][:expires_at] = Familia.now.to_i
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to eq(rewrite ? nil : organization)
        end

        it 'pins the separate explicit-session bypass even with no warm cache' do
          session['organization_id'] = organization.objid
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to eq(organization)
        end
      end
    end
  end

  [false, true].each do |header|
    context "rewritten host, #{header ? 'matching header' : 'ordinary cache'}" do
      it 'reproduces a changed membership scope without any host change' do
        load_context(allowed_domain, 'allowed.example.com', rewrite: true, header: header)
        membership.domain_scope_id = denied_domain.objid
        expect(membership.can_access_domain?(allowed_domain)).to be(false)
        warm = load_context(allowed_domain, 'allowed.example.com', rewrite: true, header: header)
        expect(warm[:organization]).to eq(organization)
        loader.clear_organization_cache(customer, session)
        cold = load_context(allowed_domain, 'allowed.example.com', rewrite: true, header: header)
        expect(cold[:organization]).to be_nil
      end

      it 'does not bypass the downstream audit entitlement gate' do
        load_context(allowed_domain, 'allowed.example.com', rewrite: true, header: header)
        context = load_context(denied_domain, 'denied.example.com', rewrite: true, header: header)
        allow(membership).to receive(:can?).with('audit_logs').and_return(false)
        expect(receipt_index).not_to receive(:rangebyscore)
        expect { receipt_logic(context).raise_concerns }.to raise_error(Onetime::EntitlementRequired)
      end
    end
  end
end
