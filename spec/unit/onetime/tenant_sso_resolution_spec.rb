# spec/unit/onetime/tenant_sso_resolution_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/tenant_sso_resolution'

# Unit coverage for the once-per-request tenant SSO resolution (#4173).
#
# The ladder itself (domain lookup → SsoConfig → tenant_sso_available_for?)
# is the one the serializers and Middleware::TenantCspExtras used to each walk
# separately; the model layer is stubbed here — no datastore. What this spec
# owns is the sharing and memoization contract those surfaces now depend on:
# one read per request, one verdict, one record.
#
# WHICH FINDER, NOT JUST WHICH ANSWER (#4157). The tri-state only exists if
# the read can fail in the resolver's sight, so the examples below assert the
# resolver calls the RAISING finder (CustomDomain.from_display_domain) — and
# one of them skips the finder stub entirely and fails the datastore seam
# under the real method, which is the only way to catch a repoint back to the
# fail-open load_by_display_domain (whose body swallows Redis::BaseError and
# StandardError, making DOMAIN_READ_FAILED unreachable).
RSpec.describe Onetime::TenantSsoResolution do
  let(:display_domain) { 'tenant.example.net' }
  let(:domain_id) { 'cd_tenant123' }
  let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }
  let(:sso_config) { instance_double(Onetime::CustomDomain::SsoConfig) }

  def stub_domain(domain = custom_domain)
    allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(domain)
  end

  def stub_failing_domain_read
    allow(OT).to receive(:le)
    allow(Onetime::CustomDomain).to receive(:from_display_domain)
      .and_raise(Redis::ConnectionError.new('Connection refused'))
  end

  def stub_sso(config = sso_config, available: true)
    allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(config)
    return if config.nil?

    allow(Onetime::CustomDomain::SsoConfig).to receive(:tenant_sso_available_for?)
      .with(domain_id, sso_config: config).and_return(available)
  end

  describe '#domain_id' do
    it 'resolves through the raising finder, which normalizes case itself' do
      stub_domain
      expect(described_class.new('Tenant.Example.NET').domain_id).to eq(domain_id)
      expect(Onetime::CustomDomain).to have_received(:from_display_domain)
        .with('Tenant.Example.NET')
    end

    it 'is nil for a blank display_domain, with no datastore read' do
      expect(Onetime::CustomDomain).not_to receive(:from_display_domain)
      expect(described_class.new(nil).domain_id).to be_nil
    end

    it 'is nil for an unregistered host' do
      stub_domain(nil)
      expect(described_class.new(display_domain).domain_id).to be_nil
    end

    it 'answers DOMAIN_READ_FAILED on a datastore error, never nil (#4157)' do
      stub_failing_domain_read

      resolution = described_class.new(display_domain)
      expect(resolution.domain_id).to eq(described_class::DOMAIN_READ_FAILED)
      expect(resolution).to be_domain_read_failed
    end

    it 'reads once and memoizes, including the nil answer' do
      stub_domain(nil)
      resolution = described_class.new(display_domain)

      3.times { resolution.domain_id }
      expect(Onetime::CustomDomain).to have_received(:from_display_domain).once
    end

    # THE READ ITSELF, NOT A STUB OF IT. Every example above stubs the finder;
    # this one lets the real CustomDomain.from_display_domain run and fails the
    # datastore seam underneath it (display_domain_index), so the swallow-vs-
    # propagate boundary is what is under test. Repoint the resolver at the
    # fail-open helper and this goes red while the stubbed examples stay green.
    it 'answers DOMAIN_READ_FAILED through the REAL finder when the index read fails' do
      allow(OT).to receive(:le)
      failing_index = instance_double(Familia::HashKey)
      allow(failing_index).to receive(:get).and_raise(Redis::BaseError.new('connection reset'))
      allow(Onetime::CustomDomain).to receive(:display_domain_index).and_return(failing_index)

      resolution = described_class.new(display_domain, :custom)
      expect(resolution.domain_id).to eq(described_class::DOMAIN_READ_FAILED)
      expect(resolution).to be_domain_read_failed
    end
  end

  describe '#sso_config' do
    it 'returns the record when the availability ladder passes' do
      stub_domain
      stub_sso
      resolution = described_class.new(display_domain)

      expect(resolution.sso_config).to equal(sso_config)
      expect(resolution).to be_available
    end

    it 'hands the loaded record to the availability check (single-read contract)' do
      stub_domain
      stub_sso
      described_class.new(display_domain).sso_config

      expect(Onetime::CustomDomain::SsoConfig).to have_received(:tenant_sso_available_for?)
        .with(domain_id, sso_config: sso_config)
    end

    it 'is nil when the ladder rejects (disabled / not permitted)' do
      stub_domain
      stub_sso(available: false)
      resolution = described_class.new(display_domain)

      expect(resolution.sso_config).to be_nil
      expect(resolution).not_to be_available
    end

    it 'is nil when the domain has no SsoConfig record' do
      stub_domain
      stub_sso(nil)
      expect(described_class.new(display_domain).sso_config).to be_nil
    end

    it 'is nil on a failed domain read, without touching SsoConfig' do
      stub_failing_domain_read
      expect(Onetime::CustomDomain::SsoConfig).not_to receive(:find_by_domain_id)

      expect(described_class.new(display_domain).sso_config).to be_nil
    end

    it 'reads once and memoizes the record' do
      stub_domain
      stub_sso
      resolution = described_class.new(display_domain)

      3.times { resolution.sso_config }
      expect(Onetime::CustomDomain).to have_received(:from_display_domain).once
      expect(Onetime::CustomDomain::SsoConfig).to have_received(:find_by_domain_id).once
      expect(Onetime::CustomDomain::SsoConfig).to have_received(:tenant_sso_available_for?).once
    end
  end

  # THE FAILURE is keyed on the classification, not the read. DomainStrategy
  # publishes display_domain unconditionally (canonical fallback), so a
  # canonical render walks this same ladder; a record keyed on the operator's
  # own host must still narrow (ADR-024,
  # signin_signup_classification_parity_spec), but a blip on such a host must
  # answer nil rather than the sentinel — otherwise domain_read_failed? hides
  # the password form on the canonical /signin. Same split the runtime gates
  # make in SigninConfig.resolve_lookup_failure.
  describe 'read failure by host classification' do
    [:canonical, :subdomain].each do |strategy|
      it "answers nil, not the sentinel, on #{strategy.inspect}" do
        stub_failing_domain_read

        resolution = described_class.new('canonical.example.com', strategy)
        expect(resolution.domain_id).to be_nil
        expect(resolution).not_to be_domain_read_failed
      end
    end

    it 'accepts the String form — the classification is not always a Symbol' do
      stub_failing_domain_read
      expect(described_class.new('canonical.example.com', 'canonical').domain_id).to be_nil
    end

    [:custom, :invalid, nil].each do |strategy|
      it "answers DOMAIN_READ_FAILED on #{strategy.inspect} — per-domain policy is unreadable" do
        stub_failing_domain_read

        resolution = described_class.new(display_domain, strategy)
        expect(resolution.domain_id).to eq(described_class::DOMAIN_READ_FAILED)
      end
    end

    it 'still reads on an operator host, so a record there keeps narrowing' do
      stub_domain
      expect(described_class.new(display_domain, :canonical).domain_id).to eq(domain_id)
    end
  end

  describe '.for' do
    it 'installs one instance on the env and returns it thereafter' do
      env   = { 'onetime.display_domain' => display_domain }
      first = described_class.for(env)

      expect(described_class.for(env)).to equal(first)
      expect(env[described_class::ENV_KEY]).to equal(first)
    end

    it 'carries the classification DomainStrategy already made' do
      stub_failing_domain_read

      resolution = described_class.for(
        'onetime.display_domain' => 'canonical.example.com',
        'onetime.domain_strategy' => :canonical,
      )
      expect(resolution.domain_strategy).to eq(:canonical)
      expect(resolution.domain_id).to be_nil
    end

    it 'reads nothing at construction — the guards upstream still short-circuit' do
      expect(Onetime::CustomDomain).not_to receive(:from_display_domain)
      described_class.for('onetime.display_domain' => display_domain)
    end

    it 'answers an unshared resolution when there is no env' do
      expect(described_class.for(nil).display_domain).to eq('')
    end
  end

  describe '.from_view_vars' do
    it 'reuses the instance the view vars carry' do
      shared = described_class.new(display_domain)
      vars   = { described_class::VIEW_VAR_KEY => shared, 'display_domain' => display_domain }

      expect(described_class.from_view_vars(vars)).to equal(shared)
    end

    it 'falls back to display_domain when view vars were built without an env' do
      stub_domain
      resolution = described_class.from_view_vars('display_domain' => display_domain)

      expect(resolution).to be_a(described_class)
      expect(resolution.domain_id).to eq(domain_id)
    end

    it 'carries the classification the view vars kept, so the fallback agrees' do
      stub_failing_domain_read

      resolution = described_class.from_view_vars(
        'display_domain' => 'canonical.example.com',
        'domain_strategy' => :canonical,
      )
      expect(resolution.domain_id).to be_nil
    end

    it 'treats a missing classification as a tenant host — the fail-closed side' do
      stub_failing_domain_read

      resolution = described_class.from_view_vars('display_domain' => display_domain)
      expect(resolution).to be_domain_read_failed
    end

    it 'ignores a non-resolution value under the key' do
      stub_domain
      vars = { described_class::VIEW_VAR_KEY => 'nonsense', 'display_domain' => display_domain }

      expect(described_class.from_view_vars(vars)).to be_a(described_class)
    end
  end
end
