# frozen_string_literal: true

# The membership's domain scope is applied to every way the loader can select
# an organization: cold selection, the O-Organization-ID header, both cache
# hits and the explicit session selection. The request's custom domains come
# from the Host header's record AND from the custom domain DomainStrategy
# resolved, so a proxy that rewrites Host to the origin target does not drop
# the check while site.network.public_host_rewrite is off.
#
# Run: tests/lanes/run unit --only spec/unit/organization_loader_cache_scope_spec.rb
require 'spec_helper'
require 'middleware/detect_host'
require 'onetime/application/organization_loader'
require 'onetime/custom_domain_resolution'
require 'onetime/middleware/public_host_rewrite'
require 'onetime/session'
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
    conf = OT.conf.to_h.merge('features' => { 'organizations' => { 'audit_logs_enabled' => true } })
    allow(OT).to receive(:conf).and_return(conf)
  end

  # A tenant request as DomainStrategy leaves it behind a proxy that rewrites
  # Host to the origin target: the display domain is the custom domain, and
  # HTTP_HOST names it only when the rewrite setting is on.
  def request_env(domain, hostname, rewrite:, header:)
    env = {
      'HTTP_HOST' => 'origin.example.com', 'SERVER_NAME' => 'origin.example.com',
      'SERVER_PORT' => '443', 'rack.url_scheme' => 'https',
      Rack::DetectHost.result_field_name => hostname,
      'onetime.display_domain' => hostname, 'onetime.domain_strategy' => :custom,
      'onetime.custom_domain' => domain,
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

  def warm_cache
    session[cache_key] = { organization_id: organization.objid, expires_at: Familia.now.to_i + 60 }
  end

  [false, true].each do |rewrite|
    [false, true].each do |header|
      context "rewrite=#{rewrite}, #{header ? 'matching header' : 'no header'}" do
        it 'selects the organization on the domain the membership is scoped to' do
          context = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to eq(organization)
          expect(session[cache_key][:expires_at]).to eq(Familia.now + described_class::CACHE_TTL)
        end

        it 'cold selection returns no organization on the sibling domain' do
          expect(membership.can_access_domain?(denied_domain)).to be(false)
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to be_nil
          expect(context[:organization_id]).to be_nil
          expect(session.key?(cache_key)).to be(false)
        end

        it 'a cache entry written on the allowed domain is not used on the sibling domain' do
          warm = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(warm[:organization]).to eq(organization)
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to be_nil
          expect(session.key?(cache_key)).to be(false)
        end

        it 'an expired cache entry is not used on the sibling domain either' do
          load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          session[cache_key][:expires_at] = Familia.now.to_i
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to be_nil
        end

        it 'the explicit session selection is not used on the sibling domain' do
          session['organization_id'] = organization.objid
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to be_nil
          # The selection is left in place: it is valid on the allowed domain.
          expect(session['organization_id']).to eq(organization.objid)
        end

        it 'the explicit session selection is used on the allowed domain' do
          session['organization_id'] = organization.objid
          context = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to eq(organization)
        end

        it 'an org-scoped member gets the organization on either domain, cold and cached' do
          membership.domain_scope_id = nil
          2.times do
            context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
            expect(context[:organization]).to eq(organization)
          end
          session['organization_id'] = organization.objid
          session.delete(cache_key)
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to eq(organization)
        end

        it 'a membership scope changed after the cache entry was written applies on the next load' do
          load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          membership.domain_scope_id = denied_domain.objid
          expect(membership.can_access_domain?(allowed_domain)).to be(false)
          context = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to be_nil
          expect(session.key?(cache_key)).to be(false)
        end
      end
    end
  end

  # With the domains feature off DomainStrategy classifies nothing, and the
  # Host header's record is the only source. The check still runs on it.
  [false, true].each do |header|
    context "domains feature off, Host names a custom domain, #{header ? 'matching header' : 'no header'}" do
      def unclassified_env(hostname, header:)
        env = { 'HTTP_HOST' => "#{hostname}:443" }
        env['HTTP_O_ORGANIZATION_ID'] = organization.objid if header
        env
      end

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('denied.example.com').and_return(denied_domain)
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('allowed.example.com').and_return(allowed_domain)
      end

      it 'selects the organization on the allowed domain' do
        context = loader.load_organization_context(customer, session, unclassified_env('allowed.example.com', header: header))
        expect(context[:organization]).to eq(organization)
      end

      it 'returns no organization on the sibling domain: cold, cached and session-selected' do
        env = unclassified_env('denied.example.com', header: header)
        expect(loader.load_organization_context(customer, session, env)[:organization]).to be_nil

        warm_cache
        expect(loader.load_organization_context(customer, session, env)[:organization]).to be_nil
        expect(session.key?(cache_key)).to be(false)

        session['organization_id'] = organization.objid
        expect(loader.load_organization_context(customer, session, env)[:organization]).to be_nil
      end

      it 'raises when the read of the Host record fails: cold, cached and session-selected' do
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('denied.example.com')
          .and_raise(Redis::CannotConnectError, 'datastore unavailable')
        env = unclassified_env('denied.example.com', header: header)
        expect { loader.load_organization_context(customer, session, env) }.to raise_error(Redis::CannotConnectError)

        warm_cache
        expect { loader.load_organization_context(customer, session, env) }.to raise_error(Redis::CannotConnectError)
        expect(session[cache_key][:organization_id]).to eq(organization.objid)

        session.delete(cache_key)
        session['organization_id'] = organization.objid
        expect { loader.load_organization_context(customer, session, env) }.to raise_error(Redis::CannotConnectError)
      end

      # Behind a proxy that rewrites Host, a failed read of the display
      # domain leaves the request :invalid with no record and a Host that
      # names no custom domain. Nothing would be checked; the failure is
      # raised instead, as it is for the Host record.
      it 'raises when the read DomainStrategy made for the display domain failed' do
        error = Redis::CannotConnectError.new('datastore unavailable')
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('origin.example.com').and_return(nil)
        env   = {
          'HTTP_HOST' => 'origin.example.com',
          'onetime.display_domain' => 'denied.example.com', 'onetime.domain_strategy' => :invalid,
          Onetime::CustomDomainResolution::ENV_KEY =>
            Onetime::CustomDomainResolution.read_failed('denied.example.com', error),
        }
        env['HTTP_O_ORGANIZATION_ID'] = organization.objid if header

        expect { loader.load_organization_context(customer, session, env) }.to raise_error(Redis::CannotConnectError)

        warm_cache
        expect { loader.load_organization_context(customer, session, env) }.to raise_error(Redis::CannotConnectError)
      end
    end
  end

  context 'a canonical request (no custom domain from either source)' do
    let(:canonical_env) do
      { 'HTTP_HOST' => 'origin.example.com', 'onetime.display_domain' => 'origin.example.com',
        'onetime.domain_strategy' => :canonical }
    end

    it 'gives a domain-scoped member the organization, cold, cached, by header and by session selection' do
      2.times do
        expect(loader.load_organization_context(customer, session, canonical_env)[:organization]).to eq(organization)
      end
      header_env = canonical_env.merge('HTTP_O_ORGANIZATION_ID' => organization.objid)
      2.times do
        expect(loader.load_organization_context(customer, session, header_env)[:organization]).to eq(organization)
      end
      session.delete(cache_key)
      session['organization_id'] = organization.objid
      expect(loader.load_organization_context(customer, session, canonical_env)[:organization]).to eq(organization)
    end

    it 'ignores a custom domain record left in the env when the strategy is not custom' do
      env = canonical_env.merge('onetime.custom_domain' => denied_domain)
      expect(loader.load_organization_context(customer, session, env)[:organization]).to eq(organization)
    end
  end

  context 'an organization on another domain than its own' do
    let(:other_org) do
      double('other organization', objid: 'org_other', archived?: false, is_default: false)
    end
    let(:foreign_domain) { double('foreign domain', objid: 'domain_foreign', primary_organization: other_org) }

    before do
      allow(other_org).to receive(:member?).with(customer).and_return(false)
    end

    # The header path already answered this way for a Host-named domain; the
    # fallback steps (default, is_default, first) now agree with it.
    it 'is not selected by the fallback steps for a domain-scoped member' do
      [false, true].each do |rewrite|
        context = load_context(foreign_domain, 'foreign.example.com', rewrite: rewrite, header: false)
        expect(context[:organization]).to be_nil
      end
    end

    it 'is selected by the fallback steps for an org-scoped member' do
      membership.domain_scope_id = nil
      context = load_context(foreign_domain, 'foreign.example.com', rewrite: false, header: false)
      expect(context[:organization]).to eq(organization)
    end
  end

  # The cache entry is written with symbol keys and the session blob is JSON,
  # so the entry read back on a later request has string keys and the loader's
  # symbol-key reads miss it. The entry is only ever hit by a second load in
  # the request that wrote it (Sessions::TrackMetadata at commit).
  describe 'the cache entry across requests (real session store)' do
    let(:store) { Onetime::Session.new(->(_env) { [200, {}, []] }, secret: 'x' * 64) }
    let(:rack_request) { Rack::Request.new(Rack::MockRequest.env_for('/')) }

    it 'comes back with string keys and is treated as a miss' do
      env = request_env(allowed_domain, 'allowed.example.com', rewrite: true, header: false)
      loader.load_organization_context(customer, session, env)
      expect(session[cache_key].keys).to eq([:organization_id, :expires_at])

      sid = store.send(:generate_sid)
      store.send(:write_session, rack_request, sid, session, {})
      _sid, reloaded = store.send(:find_session, rack_request, sid)

      expect(reloaded[cache_key]).to eq(
        'organization_id' => organization.objid, 'expires_at' => Familia.now.to_i + described_class::CACHE_TTL,
      )
      expect(reloaded[cache_key][:expires_at]).to be_nil

      # A miss: the cold path runs and replaces the entry with a symbol-keyed one.
      context = loader.load_organization_context(customer, reloaded, env)
      expect(context[:organization]).to eq(organization)
      expect(reloaded[cache_key].keys).to eq([:organization_id, :expires_at])
    ensure
      store.send(:delete_session, rack_request, sid, {}) if sid
    end
  end

  # What a logic class sees after the loader returned no organization.
  # Logic::OrganizationContext#auth_org asks EnsureDefaultWorkspace, which
  # creates nothing for a customer who already has an organization, and then
  # falls back to the customer's first organization.
  describe 'auth_org after the loader returned no organization' do
    def receipt_logic(context)
      result = double('strategy result', user: customer, session: session,
        metadata: { organization_context: context, domain_strategy: :custom,
          display_domain: 'denied.example.com', custom_domain_id: denied_domain.objid })
      V2::Logic::Secrets::ListReceipts.new(result, { 'scope' => 'org' })
    end

    it 'pins the fallback: the first organization is returned without a scope check' do
      allow(customer).to receive(:provisioning_failed?).and_return(false)
      allow(customer).to receive(:clear_provisioning_failure!)
      context = load_context(denied_domain, 'denied.example.com', rewrite: false, header: false)
      expect(context[:organization]).to be_nil

      logic = receipt_logic(context)
      expect(logic.organization).to be_nil
      expect(logic.auth_org).to eq(organization)
    end
  end
end
