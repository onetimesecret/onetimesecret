# spec/integration/all/domains/caddy_on_demand_certificate_gate_spec.rb
#
# frozen_string_literal: true

# The caddy_on_demand certificate gate, end to end.
#
# Caddy asks the internal ACME endpoint (apps/internal/acme) before it obtains
# a certificate for a hostname. The endpoint says yes only when
# CustomDomain#ready? is true, which needs `verified` (the TXT ownership check)
# and `resolving` (the status probe). Each piece has its own unit coverage;
# this file runs them together, with nothing between the config and the HTTP
# answer replaced:
#
#   features.domains.validation_strategy = caddy_on_demand
#     -> DomainRefreshJob.refresh_domains        (real page walk)
#     -> Operations::VerifyDomain                (real, bulk mode, persisting)
#     -> DomainValidation::Strategy.for_config   (real CaddyOnDemandStrategy)
#     -> DomainValidation::TxtVerifier           (real, over a scripted resolver)
#     -> CustomDomain in Valkey                  (real)
#     -> GET /ask on Internal::ACME::Application (real app, real lookup)
#
# The two network seams are scripted: TxtResolver (the DNS transport under
# TxtVerifier) and TlsProbe (address lookup + TLS handshake). DnsStubResolver
# is the only DNS transport either uses, so the example group fails if one is
# ever built.

require 'spec_helper'
require 'rack/test'
require 'securerandom'
require 'onetime/operations/verify_domain'
require 'onetime/domain_validation/strategy'
require 'onetime/jobs/scheduled/domain_refresh_job'
require_relative '../../../../apps/internal/acme/application'

RSpec.describe 'Caddy on-demand certificate gate', :shared_db_state, type: :integration do
  include Rack::Test::Methods

  # Scripted stand-in for DomainValidation::TxtResolver, keyed by hostname.
  # The example group shares its datastore, so the page walk can pick up
  # domains other specs left behind. A hostname this resolver was not told
  # about gets no reply (indeterminate), which keeps the run from storing a
  # scripted "no record" on rows that are not ours.
  let(:resolver_class) do
    Class.new do
      attr_reader :records, :failures, :lookups

      def initialize
        @records  = {}
        @failures = {}
        @lookups  = []
      end

      def lookup(hostname)
        @lookups << hostname
        raise failures[hostname] if failures[hostname].is_a?(Exception)
        unless records.key?(hostname) || failures.key?(hostname)
          raise Onetime::DomainValidation::TxtResolver::NoReplyError, "unscripted hostname #{hostname}"
        end

        values = records.fetch(hostname, [])
        rcode  = failures[hostname] || (values.empty? ? Resolv::DNS::RCode::NXDomain : Resolv::DNS::RCode::NoError)
        Onetime::DomainValidation::TxtResolver::Answer.new(rcode: rcode, values: values)
      end

      def close; end
    end
  end

  # Scripted stand-in for DomainValidation::TlsProbe. The default is a name
  # that resolves and has no certificate yet: the state every domain is in
  # when Caddy asks for the first time. Any other hostname "could not be
  # probed", for the same reason the resolver stays silent about it.
  let(:probe_class) do
    Class.new do
      attr_accessor :is_resolving, :has_ssl

      def initialize(hostname)
        @hostname     = hostname
        @is_resolving = true
        @has_ssl      = false
      end

      def probe(hostname)
        result = Onetime::DomainValidation::TlsProbe::Result
        return result.new(is_resolving: nil, has_ssl: nil, message: 'unscripted') unless hostname == @hostname

        result.new(is_resolving: is_resolving, has_ssl: has_ssl, addresses: ['93.184.216.34'], message: 'scripted')
      end
    end
  end

  let(:resolver) { resolver_class.new }
  let(:probe) { probe_class.new(hostname) }
  let(:app) { Internal::ACME::Application.new }

  let(:suffix) { "#{Familia.now.to_i}-#{SecureRandom.hex(3)}" }
  let(:owner) { Onetime::Customer.create!(email: "caddy_gate_#{suffix}@example.com") }
  let(:organization) do
    org = Onetime::Organization.create!('Caddy Gate Corp', owner, "caddy_gate_#{suffix}@corp.example.com")
    org.define_singleton_method(:billing_enabled?) { false }
    org
  end
  let(:hostname) { "secrets-#{suffix}.example.com" }
  let!(:domain) { Onetime::CustomDomain.create!(hostname, organization.objid) }

  before(:all) do
    Onetime.boot! :test
  end

  before do
    @saved_conf = YAML.load(YAML.dump(OT.conf))
    conf        = YAML.load(YAML.dump(OT.conf))
    ((conf['features'] ||= {})['domains'] ||= {})['validation_strategy'] = 'caddy_on_demand'
    # One page, always. The page is derived from the clock, and a domain that
    # is verified and resolving is not in the warm-up set, so with the default
    # batch_size and enough leftover domains a later refresh! would reach ours
    # only on some wall-clock ticks.
    (conf['jobs'] ||= {})['domain_refresh']                               = { 'enabled' => true, 'batch_size' => 100_000 }
    # Promotion into :verified would otherwise fetch the domain's favicon,
    # which is an outbound request to the hostname.
    conf['jobs']['favicon_fetch']                                         = { 'enabled' => false }
    OT.send(:conf=, conf)

    # The ACME app's own concern is the ask route; the universal stack needs
    # locale data this file has no use for (same as the app's own spec).
    allow(Onetime::Application::MiddlewareStack).to receive(:configure)

    allow(Onetime::DomainValidation::TxtResolver).to receive(:new).and_return(resolver)
    allow(Onetime::DomainValidation::TlsProbe).to receive(:new).and_return(probe)
    expect(Onetime::DomainValidation::DnsStubResolver).not_to receive(:new)
    expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_favicon_fetch)

    # Ours, and without a record until an example publishes one.
    resolver.records[domain.validation_record] = []
  end

  after do
    OT.send(:conf=, @saved_conf) if @saved_conf
    domain.destroy!
    organization.destroy!
    owner.destroy!
  end

  # Every example reads state this run is supposed to have written, so a run
  # that did not visit the domain fails here rather than in a later assertion.
  def refresh!
    resolver.lookups.clear
    Onetime::Jobs::Scheduled::DomainRefreshJob.send(:refresh_domains)
    expect(resolver.lookups).to include(domain.validation_record)
  end

  def stored
    Onetime::CustomDomain.find_by_identifier(domain.identifier)
  end

  def ask
    get '/ask', domain: hostname
    last_response.status
  end

  def publish_txt_record
    resolver.records[domain.validation_record] = [domain.txt_validation_value]
  end

  it 'builds the configured strategy and declares no pacing for it' do
    strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)

    expect(strategy).to be_a(Onetime::DomainValidation::CaddyOnDemandStrategy)
    expect(strategy.bulk_rate_limit).to eq(0)
  end

  it 'refuses a registered domain that has never been checked' do
    expect(ask).to eq(403)
  end

  context 'without the TXT record' do
    it 'stays unverified, and the ask endpoint refuses, even though the name resolves' do
      refresh!

      expect(resolver.lookups).to include(domain.validation_record)
      expect(stored.verified).to be(false)
      expect(stored.resolving).to be(true)
      expect(stored.ready?).to be(false)
      expect(ask).to eq(403)
    end

    it 'is not satisfied by a TXT record with some other value' do
      resolver.records[domain.validation_record] = ['not-the-challenge']
      refresh!

      expect(stored.verified).to be(false)
      expect(ask).to eq(403)
    end
  end

  context 'with the TXT record published and the name resolving' do
    before { publish_txt_record }

    it 'becomes verified and ready, and the ask endpoint allows the first certificate' do
      refresh!

      expect(stored.verified).to be(true)
      expect(stored.resolving).to be(true)
      expect(stored.ready?).to be(true)
      expect(stored.verified_confirmed_at).to be_within(5).of(Familia.now.to_i)
      # No certificate exists before Caddy is allowed to obtain one, so
      # has_ssl: false must not hold the gate shut.
      expect(JSON.parse(stored.vhost)).to include('has_ssl' => false, 'status' => 'PENDING_SSL')
      expect(ask).to eq(200)
    end

    it 'refuses while the name does not resolve' do
      probe.is_resolving = false
      refresh!

      expect(stored.verified).to be(true)
      expect(stored.ready?).to be(false)
      expect(ask).to eq(403)
    end

    context 'when the record is later removed' do
      before do
        refresh!
        resolver.records[domain.validation_record] = []
      end

      it 'is demoted, and the ask endpoint refuses again' do
        expect { refresh! }.to change { stored.verified }.from(true).to(false)

        expect(stored.ready?).to be(false)
        expect(ask).to eq(403)
      end

      it 'is held by an operator override' do
        held                      = stored
        held.verified_by_override = true
        held.save

        refresh!

        expect(stored.verified).to be(true)
        expect(stored.verified_by_override).to be(true)
        expect(ask).to eq(200)
      end
    end

    context 'when later lookups are indeterminate' do
      before { refresh! }

      it 'holds the stored state through a SERVFAIL' do
        resolver.failures[domain.validation_record] = Resolv::DNS::RCode::ServFail
        refresh!

        expect(stored.verified).to be(true)
        expect(stored.verified_unconfirmed_since).to be_within(5).of(Familia.now.to_i)
        expect(ask).to eq(200)
      end

      it 'holds the stored state through a resolver timeout and a probe that could not tell' do
        resolver.failures[domain.validation_record] =
          Onetime::DomainValidation::TxtResolver::NoReplyError.new('no reply')
        probe.is_resolving                          = nil
        probe.has_ssl                               = nil
        refresh!

        expect(stored.verified).to be(true)
        expect(stored.resolving).to be(true)
        expect(stored.vhost_fetch_failed_at.to_i).to be_positive
        expect(ask).to eq(200)
      end

      it 'withdraws verified once the lookups have been indeterminate past the confirmation window' do
        resolver.failures[domain.validation_record] = Resolv::DNS::RCode::ServFail
        stale                                       = stored
        stale.verified_unconfirmed_since            =
          Familia.now.to_i - Onetime::Operations::VerifyDomain::ConfirmationWindow::MAX_AGE - 60
        stale.save

        refresh!

        expect(stored.verified).to be(false)
        expect(ask).to eq(403)
      end
    end
  end

  # `verified` as the strategy stored it before it checked the TXT record:
  # set, with no confirmation on record. An indeterminate lookup has no
  # earlier proof to protect here, and `resolving` is now filled in by the
  # probe, so holding the flag would open the gate.
  context 'with verified set before any TXT check confirmed it' do
    before do
      legacy          = stored
      legacy.verified = true
      legacy.save
      resolver.failures[domain.validation_record] = Resolv::DNS::RCode::ServFail
    end

    it 'does not hold verified through an indeterminate lookup, and the ask endpoint refuses' do
      expect(stored.verified_confirmed_at).to be_nil

      refresh!

      expect(stored.verified).to be(false)
      expect(stored.resolving).to be(true)
      expect(stored.ready?).to be(false)
      expect(ask).to eq(403)
    end

    it 'is held by an operator override' do
      held                      = stored
      held.verified_by_override = true
      held.save

      refresh!

      expect(stored.verified).to be(true)
      expect(stored.verified_by_override).to be(true)
      expect(ask).to eq(200)
    end

    it 'is confirmed by the record once the lookup answers' do
      resolver.failures.clear
      publish_txt_record

      refresh!

      expect(stored.verified).to be(true)
      expect(stored.verified_confirmed_at).to be_within(5).of(Familia.now.to_i)
      expect(ask).to eq(200)
    end
  end

  it 'never promotes on an indeterminate lookup' do
    resolver.failures[domain.validation_record] = Resolv::DNS::RCode::ServFail
    refresh!

    expect(stored.verified).not_to be(true)
    expect(stored.verified_unconfirmed_since).to be_nil
    expect(ask).to eq(403)
  end
end
