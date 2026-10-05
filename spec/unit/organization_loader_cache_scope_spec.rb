# frozen_string_literal: true

# The membership's domain scope is applied to every way the loader can select
# an organization: the fallback steps, the O-Organization-ID header and the
# explicit session selection. The request's custom domains come from the Host
# header's record AND from the custom domain DomainStrategy resolved, so a
# proxy that rewrites Host to the origin target does not drop the check while
# site.network.public_host_rewrite is off.
#
# The loader keeps no cache in the session (the file name predates that):
# every load reads membership, archived state and scope again. The explicit
# selection in session['organization_id'] is what persists, and the blocks
# at the end cover how it is written, read back and cleared (#4565).
#
# Run: tests/lanes/run unit --only spec/unit/organization_loader_cache_scope_spec.rb
require 'spec_helper'
require 'middleware/detect_host'
require 'onetime/application/organization_loader'
require 'onetime/application/request_helpers'
require 'onetime/middleware/domain_strategy'
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
      Onetime::CustomDomain::Lookup::ENV_KEY => Onetime::CustomDomain::Lookup.found(hostname, domain),
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

  [false, true].each do |rewrite|
    [false, true].each do |header|
      context "rewrite=#{rewrite}, #{header ? 'matching header' : 'no header'}" do
        it 'selects the organization on the domain the membership is scoped to' do
          context = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to eq(organization)
          expect(context[:scope_domains]).to eq([allowed_domain])
          # Nothing is remembered in the session: the next load resolves again.
          expect(session).to eq({})
        end

        it 'returns no organization on the sibling domain' do
          expect(membership.can_access_domain?(denied_domain)).to be(false)
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to be_nil
          expect(context[:organization_id]).to be_nil
          expect(session).to eq({})
        end

        it 'a load on the allowed domain does not carry over to the sibling domain' do
          first = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(first[:organization]).to eq(organization)
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

        it 'an org-scoped member gets the organization on either domain, on repeated loads' do
          membership.domain_scope_id = nil
          2.times do
            context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
            expect(context[:organization]).to eq(organization)
          end
          session['organization_id'] = organization.objid
          context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to eq(organization)
        end

        it 'a membership scope changed between two loads applies on the second' do
          first = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(first[:organization]).to eq(organization)
          membership.domain_scope_id = denied_domain.objid
          expect(membership.can_access_domain?(allowed_domain)).to be(false)
          context = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to be_nil
        end

        it 'a membership removed between two loads applies on the second' do
          first = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(first[:organization]).to eq(organization)
          allow(organization).to receive(:member?).with(customer).and_return(false)
          allow(customer).to receive(:organization_instances).and_return([])
          context = load_context(allowed_domain, 'allowed.example.com', rewrite: rewrite, header: header)
          expect(context[:organization]).to be_nil
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

      it 'returns no organization on the sibling domain: unselected and session-selected' do
        env = unclassified_env('denied.example.com', header: header)
        expect(loader.load_organization_context(customer, session, env)[:organization]).to be_nil

        session['organization_id'] = organization.objid
        expect(loader.load_organization_context(customer, session, env)[:organization]).to be_nil
      end

      it 'raises when the read of the Host record fails: unselected and session-selected' do
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('denied.example.com')
          .and_raise(Redis::CannotConnectError, 'datastore unavailable')
        env = unclassified_env('denied.example.com', header: header)
        expect { loader.load_organization_context(customer, session, env) }.to raise_error(Redis::CannotConnectError)

        session['organization_id'] = organization.objid
        expect { loader.load_organization_context(customer, session, env) }.to raise_error(Redis::CannotConnectError)
        # The selection is not dropped by a failed read.
        expect(session['organization_id']).to eq(organization.objid)
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
          Onetime::CustomDomain::Lookup::ENV_KEY =>
            Onetime::CustomDomain::Lookup.read_failed('denied.example.com', error),
        }
        env['HTTP_O_ORGANIZATION_ID'] = organization.objid if header

        expect { loader.load_organization_context(customer, session, env) }.to raise_error(Redis::CannotConnectError)
      end
    end
  end

  context 'a canonical request (no custom domain from either source)' do
    let(:canonical_env) do
      { 'HTTP_HOST' => 'origin.example.com', 'onetime.display_domain' => 'origin.example.com',
        'onetime.domain_strategy' => :canonical }
    end

    it 'gives a domain-scoped member the organization, repeatedly, by header and by session selection' do
      2.times do
        expect(loader.load_organization_context(customer, session, canonical_env)[:organization]).to eq(organization)
      end
      header_env = canonical_env.merge('HTTP_O_ORGANIZATION_ID' => organization.objid)
      2.times do
        expect(loader.load_organization_context(customer, session, header_env)[:organization]).to eq(organization)
      end
      session['organization_id'] = organization.objid
      expect(loader.load_organization_context(customer, session, canonical_env)[:organization]).to eq(organization)
    end

    it 'ignores a custom domain record left in the env when the strategy is not custom' do
      env = canonical_env.merge('onetime.custom_domain' => denied_domain)
      expect(loader.load_organization_context(customer, session, env)[:organization]).to eq(organization)
    end

    context 'when the custom-domain index is unavailable', :aggregate_failures do
      before do
        conf = OT.conf.to_h.merge(
          'site' => { 'host' => 'origin.example.com:443' },
          'features' => { 'domains' => { 'default' => 'links.example.com', 'link_domains' => ['go.example.net'] } },
        )
        allow(OT).to receive(:conf).and_return(conf)
      end

      ['origin.example.com', 'links.example.com', 'GO.EXAMPLE.NET:443', 'www.example.com'].each do |host|
        [:unselected, :header, :session].each do |selection|
          it "uses #{selection} selection on #{host} without reading the custom-domain index" do
            env = canonical_env.merge('HTTP_HOST' => host, 'onetime.display_domain' => host.split(':').first.downcase)
            env['HTTP_O_ORGANIZATION_ID'] = organization.objid if selection == :header
            session['organization_id']    = organization.objid if selection == :session
            allow(Onetime::CustomDomain).to receive(:from_display_domain).with(host.split(':').first.downcase)
              .and_raise(Redis::CannotConnectError, 'domain index unavailable')

            context                       = loader.load_organization_context(customer, session, env)
            expect(context[:organization]).to eq(organization)
            expect(context).not_to have_key(:domain_scope_refused)
            expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
          end
        end
      end

      it 'does not read for a canonical www Host when the display host is a different canonical host' do
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('www.example.com')
          .and_raise(Redis::CannotConnectError, 'domain index unavailable')
        %w[www.example.com links.example.com].each do |host|
          strategy = Onetime::Middleware::DomainStrategy::Chooserator.choose_strategy(
            host,
            Onetime::Utils::CanonicalHosts.hosts,
            anchor_domains: Onetime::Utils::CanonicalHosts.anchor_hosts,
          )
          expect(strategy).to eq(:canonical)
        end
        env = canonical_env.merge('HTTP_HOST' => 'www.example.com:443', 'onetime.display_domain' => 'links.example.com')
        expect(loader.load_organization_context(customer, session, env)[:organization]).to eq(organization)
        expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
      end

      it 'does not bypass a tenant www sibling of a link-pool host' do
        env = canonical_env.merge('HTTP_HOST' => 'www.example.net:443')
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('www.example.net').and_return(denied_domain)
        context = loader.load_organization_context(customer, session, env)
        expect(context[:organization]).to be_nil
        expect(context[:domain_scope_refused]).to be(true)
      end

      it 'does not need a middleware classification for an exact configured canonical host' do
        env = { 'HTTP_HOST' => 'origin.example.com:443' }
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('origin.example.com')
          .and_raise(Redis::CannotConnectError, 'domain index unavailable')

        expect(loader.load_organization_context(customer, session, env)[:organization]).to eq(organization)
        expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
      end

      it 'still checks a custom display domain when Host is a configured canonical origin' do
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('origin.example.com')
          .and_raise(Redis::CannotConnectError, 'domain index unavailable')
        context = load_context(denied_domain, 'denied.example.com', rewrite: false, header: false)

        expect(context[:organization]).to be_nil
        expect(context[:domain_scope_refused]).to be(true)
        expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
      end

      it 'still raises for a failed display-domain read behind a configured canonical origin' do
        error = Redis::CannotConnectError.new('domain index unavailable')
        env   = canonical_env.merge(
          'onetime.display_domain' => 'denied.example.com',
          'onetime.domain_strategy' => :invalid,
          Onetime::CustomDomain::Lookup::ENV_KEY =>
            Onetime::CustomDomain::Lookup.read_failed('denied.example.com', error),
        )
        expect { loader.load_organization_context(customer, session, env) }.to raise_error(error)
      end

      it 'does not treat a different raw tenant Host as canonical when middleware displays the origin' do
        env = canonical_env.merge('HTTP_HOST' => 'denied.example.com:443')
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('denied.example.com').and_return(denied_domain)
        context = loader.load_organization_context(customer, session, env)
        expect(context[:organization]).to be_nil
        expect(context[:domain_scope_refused]).to be(true)
      end

      it 'still raises if the lookup of that raw tenant Host fails' do
        env = canonical_env.merge('HTTP_HOST' => 'denied.example.com:443')
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('denied.example.com')
          .and_raise(Redis::CannotConnectError, 'domain index unavailable')
        expect { loader.load_organization_context(customer, session, env) }.to raise_error(Redis::CannotConnectError)
      end
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

  # The explicit selection (#4565). `organization` stays the customer's first
  # organization, so it is what the fallback steps choose; `selected_org` is
  # only ever reached through session['organization_id'] and `header_org`
  # only through the header.
  describe 'the explicit session selection' do
    let(:selected_org) do
      double('selected organization', objid: 'org_selected', archived?: false, is_default: false)
    end
    let(:header_org) do
      double('header organization', objid: 'org_header', archived?: false, is_default: false)
    end
    let(:customer) do
      double('customer', objid: 'customer_scoped', custid: 'scoped@example.com',
        extid: 'customer_external', anonymous?: false, default_org_id: '',
        organization_instances: [organization, selected_org, header_org])
    end
    let(:canonical_env) do
      { 'HTTP_HOST' => 'origin.example.com', 'onetime.display_domain' => 'origin.example.com',
        'onetime.domain_strategy' => :canonical }
    end
    let(:canonical_context) { loader.load_organization_context(customer, session, canonical_env) }

    before do
      [selected_org, header_org].each do |org|
        allow(Onetime::Organization).to receive(:load).with(org.objid).and_return(org)
        allow(org).to receive(:member?).with(customer).and_return(true)
        # Org-scoped memberships: no domain restriction.
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with(org.objid, customer.objid).and_return(Onetime::OrganizationMembership.new)
      end
      allow(Onetime::Organization).to receive(:load).with('org_unknown').and_return(nil)
    end

    describe 'across requests (real session store)' do
      let(:store) { Onetime::Session.new(->(_env) { [200, {}, []] }, secret: 'x' * 64) }
      let(:rack_request) { Rack::Request.new(Rack::MockRequest.env_for('/')) }

      it 'is read back from the stored session and decides a request with no header' do
        expect(canonical_context[:organization]).to eq(organization)
        expect(loader.select_organization(customer, session, selected_org.objid, canonical_context)).to eq(selected_org)
        expect(session).to eq('organization_id' => selected_org.objid)

        sid = store.send(:generate_sid)
        store.send(:write_session, rack_request, sid, session, {})
        _sid, reloaded = store.send(:find_session, rack_request, sid)

        # A plain string under a string key: the JSON round trip changes nothing.
        expect(reloaded['organization_id']).to eq(selected_org.objid)

        context = loader.load_organization_context(customer, reloaded, canonical_env)
        expect(context[:organization]).to eq(selected_org)
        expect(context[:organization_id]).to eq(selected_org.objid)
        expect(reloaded['organization_id']).to eq(selected_org.objid)
      ensure
        store.send(:delete_session, rack_request, sid, {}) if sid
      end

      it 'does not read a leftover org_context entry in an older session' do
        session["org_context:#{customer.objid}"] = {
          'organization_id' => selected_org.objid, 'expires_at' => Familia.now.to_i + 300
        }
        sid            = store.send(:generate_sid)
        store.send(:write_session, rack_request, sid, session, {})
        _sid, reloaded = store.send(:find_session, rack_request, sid)

        context = loader.load_organization_context(customer, reloaded, canonical_env)
        expect(context[:organization]).to eq(organization)
      ensure
        store.send(:delete_session, rack_request, sid, {}) if sid
      end
    end

    describe 'precedence' do
      it 'is header, then session selection, then the default' do
        expect(loader.load_organization_context(customer, session, canonical_env)[:organization]).to eq(organization)

        session['organization_id'] = selected_org.objid
        expect(loader.load_organization_context(customer, session, canonical_env)[:organization]).to eq(selected_org)

        header_env = canonical_env.merge('HTTP_O_ORGANIZATION_ID' => header_org.objid)
        expect(loader.load_organization_context(customer, session, header_env)[:organization]).to eq(header_org)

        # The header decided its own request only.
        expect(session).to eq('organization_id' => selected_org.objid)
        expect(loader.load_organization_context(customer, session, canonical_env)[:organization]).to eq(selected_org)
      end

      it 'falls from a refused header to the session selection' do
        session['organization_id'] = selected_org.objid
        allow(header_org).to receive(:member?).with(customer).and_return(false)
        header_env                 = canonical_env.merge('HTTP_O_ORGANIZATION_ID' => header_org.objid)

        expect(loader.load_organization_context(customer, session, header_env)[:organization]).to eq(selected_org)
      end

      it 'does not let the header select an archived organization' do
        allow(header_org).to receive(:archived?).and_return(true)
        header_env = canonical_env.merge('HTTP_O_ORGANIZATION_ID' => header_org.objid)

        expect(loader.load_organization_context(customer, session, header_env)[:organization]).to eq(organization)
      end
    end

    describe 'when the selection stops being valid' do
      before { session['organization_id'] = selected_org.objid }

      it 'is cleared once the membership is revoked' do
        allow(selected_org).to receive(:member?).with(customer).and_return(false)
        allow(customer).to receive(:organization_instances).and_return([organization, header_org])

        context = loader.load_organization_context(customer, session, canonical_env)
        expect(context[:organization]).to eq(organization)
        expect(session).not_to have_key('organization_id')
      end

      it 'is cleared once the organization is archived' do
        allow(selected_org).to receive(:archived?).and_return(true)

        context = loader.load_organization_context(customer, session, canonical_env)
        expect(context[:organization]).to eq(organization)
        expect(session).not_to have_key('organization_id')
      end

      it 'is cleared once the organization no longer exists' do
        allow(Onetime::Organization).to receive(:load).with(selected_org.objid).and_return(nil)

        context = loader.load_organization_context(customer, session, canonical_env)
        expect(context[:organization]).to eq(organization)
        expect(session).not_to have_key('organization_id')
      end
    end

    describe '#select_organization' do
      it 'records the objid and returns the organization' do
        expect(loader.select_organization(customer, session, selected_org.objid, canonical_context)).to eq(selected_org)
        expect(session['organization_id']).to eq(selected_org.objid)
      end

      it 'is callable on the module itself' do
        selected = described_class.select_organization(customer, session, selected_org.objid, canonical_context)
        expect(selected).to eq(selected_org)
        expect(session['organization_id']).to eq(selected_org.objid)
      end

      context 'when refused' do
        before { session['organization_id'] = organization.objid }

        after { expect(session).to eq('organization_id' => organization.objid) }

        it 'refuses an organization the customer is not a member of' do
          allow(selected_org).to receive(:member?).with(customer).and_return(false)
          expect(loader.select_organization(customer, session, selected_org.objid, canonical_context)).to be_nil
        end

        it 'refuses an archived organization' do
          allow(selected_org).to receive(:archived?).and_return(true)
          expect(loader.select_organization(customer, session, selected_org.objid, canonical_context)).to be_nil
        end

        it 'refuses an unknown organization' do
          expect(loader.select_organization(customer, session, 'org_unknown', canonical_context)).to be_nil
        end

        it 'refuses a blank or non-string id' do
          ['', nil, 42].each do |org_id|
            expect(loader.select_organization(customer, session, org_id, canonical_context)).to be_nil
          end
        end

        it 'refuses an organization the domain scope does not permit on a custom domain' do
          # A membership scoped to the allowed domain, selecting on the sibling.
          allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
            .with(selected_org.objid, customer.objid)
            .and_return(Onetime::OrganizationMembership.new(domain_scope_id: allowed_domain.objid))
          context = load_context(denied_domain, 'denied.example.com', rewrite: false, header: false)
          expect(context[:scope_domains]).to eq([denied_domain])

          expect(loader.select_organization(customer, session, selected_org.objid, context)).to be_nil
        end

        it 'refuses when the request carries no loader context, so the scope is unknown' do
          [nil, {}, { organization: organization }].each do |context|
            expect(loader.select_organization(customer, session, selected_org.objid, context)).to be_nil
          end
        end
      end

      it 'accepts the same organization on the domain its membership is scoped to' do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with(selected_org.objid, customer.objid)
          .and_return(Onetime::OrganizationMembership.new(domain_scope_id: allowed_domain.objid))
        context = load_context(allowed_domain, 'allowed.example.com', rewrite: false, header: false)

        expect(loader.select_organization(customer, session, selected_org.objid, context)).to eq(selected_org)
        expect(session['organization_id']).to eq(selected_org.objid)
      end
    end

    # The request helper is the same write for code that holds a request.
    describe 'RequestHelpers#switch_organization' do
      let(:strategy_result) do
        double('strategy result', user: customer, session: session, authenticated?: true,
          metadata: { organization_context: canonical_context })
      end
      let(:request) do
        Struct.new(:env).new({ 'otto.strategy_result' => strategy_result })
          .extend(Onetime::Application::RequestHelpers)
      end

      it 'records the selection and reports success' do
        expect(request.switch_organization(selected_org.objid)).to be(true)
        expect(session['organization_id']).to eq(selected_org.objid)
        expect(request.organization).to eq(selected_org)
      end

      it 'refuses an archived organization and leaves the session as it was' do
        allow(selected_org).to receive(:archived?).and_return(true)
        expect(request.switch_organization(selected_org.objid)).to be(false)
        expect(session).not_to have_key('organization_id')
      end
    end
  end

  # What a logic class sees after the loader returned no organization.
  # The loader marks a scope refusal in the context, and
  # Logic::OrganizationContext#auth_org returns nil for it instead of falling
  # back to the customer's first organization.
  describe 'auth_org after the loader returned no organization' do
    def receipt_logic(context, params = { 'scope' => 'org' })
      result = double('strategy result', user: customer, session: session,
        metadata: { organization_context: context, domain_strategy: :custom,
          display_domain: 'denied.example.com', custom_domain_id: denied_domain.objid })
      V2::Logic::Secrets::ListReceipts.new(result, params)
    end

    before do
      allow(customer).to receive(:provisioning_failed?).and_return(false)
      allow(customer).to receive(:clear_provisioning_failure!)
    end

    [false, true].each do |rewrite|
      it "keeps the refusal on the sibling domain (rewrite=#{rewrite})" do
        context = load_context(denied_domain, 'denied.example.com', rewrite: rewrite, header: false)
        expect(context[:organization]).to be_nil
        expect(context[:domain_scope_refused]).to be(true)

        expect(Auth::Operations::EnsureDefaultWorkspace).not_to receive(:new)
        logic = receipt_logic(context)
        expect(logic.auth_org).to be_nil
        expect(logic.auth_membership).to be_nil
        expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired)
      end
    end

    it 'does not mark a refusal when an organization was selected' do
      context = load_context(allowed_domain, 'allowed.example.com', rewrite: false, header: false)
      expect(context).not_to have_key(:domain_scope_refused)
      expect(receipt_logic(context).auth_org).to eq(organization)
    end

    it 'does not mark a refusal on a canonical request' do
      allow(customer).to receive(:organization_instances).and_return([])
      env     = { 'HTTP_HOST' => 'origin.example.com', 'onetime.display_domain' => 'origin.example.com',
                  'onetime.domain_strategy' => :canonical }
      context = loader.load_organization_context(customer, session, env)
      expect(context[:organization]).to be_nil
      expect(context).not_to have_key(:domain_scope_refused)
    end

    it 'still falls back for a customer with no scope refusal (the lazy-creation race)' do
      workspace = instance_double(Auth::Operations::EnsureDefaultWorkspace, call: nil)
      allow(Auth::Operations::EnsureDefaultWorkspace).to receive(:new).and_return(workspace)
      logic     = receipt_logic({ organization: nil, organization_id: nil })
      expect(logic.auth_org).to eq(organization)
    end
  end
end
