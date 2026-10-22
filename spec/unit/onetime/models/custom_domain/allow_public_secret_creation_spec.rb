# spec/unit/onetime/models/custom_domain/allow_public_secret_creation_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Decision table for CustomDomain#allow_public_secret_creation? — the
# authorization gate consumed by the anonymous secret-creation API
# (base_secret_action#validate_domain_permissions). It must authorize the
# public create form ONLY for an enabled homepage in a recognised create
# mode, and fail CLOSED in every other case: missing config, disabled,
# incoming mode, or a corrupt/unrecognised stored secrets_mode.
#
# The end-to-end path also has try-file coverage
# (try/unit/models/custom_domain/homepage_config_try.rb); this keeps the
# gate's decision table self-contained in the RSpec unit suite, exercising
# the real HomepageConfig predicates (enabled? / recognized_secrets_mode? /
# incoming_mode?) without touching Redis.
RSpec.describe Onetime::CustomDomain, '#allow_public_secret_creation?' do
  subject(:domain) do
    cd = described_class.new
    allow(cd).to receive(:identifier).and_return('domain123')
    cd
  end

  # Return a real HomepageConfig from the class finder so the gate runs the
  # genuine predicate logic rather than stubbed booleans.
  def stub_homepage_config(enabled:, secrets_mode:, allowed_cidrs: nil, denied_cidrs: nil)
    config = Onetime::CustomDomain::HomepageConfig.new(
      domain_id: 'domain123', enabled: enabled, secrets_mode: secrets_mode
    )
    config.allowed_cidrs = allowed_cidrs unless allowed_cidrs.nil?
    config.denied_cidrs  = denied_cidrs unless denied_cidrs.nil?
    allow(Onetime::CustomDomain::HomepageConfig)
      .to receive(:find_by_domain_id).with('domain123').and_return(config)
    config
  end

  # A stand-in for the env['otto.ip_match'] verdict closure: membership of
  # ONE client IP in the ranges handed over, family-aware.
  def matcher_for(ip)
    addr = IPAddr.new(ip)
    ->(ranges) { ranges.any? { |range| range.family == addr.family && range.include?(addr) } }
  end

  context 'when the homepage config record is missing' do
    it 'fails closed rather than assuming a public create form' do
      allow(Onetime::CustomDomain::HomepageConfig)
        .to receive(:find_by_domain_id).with('domain123').and_return(nil)
      allow(OT).to receive(:le)

      expect(domain.allow_public_secret_creation?).to be(false)
    end
  end

  context 'when enabled in create mode' do
    it 'authorizes anonymous secret creation' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'create')
      expect(domain.allow_public_secret_creation?).to be(true)
    end
  end

  context 'when enabled with a blank (legacy/unset) secrets_mode' do
    it 'authorizes creation, reading blank as the historical create form' do
      stub_homepage_config(enabled: 'true', secrets_mode: '')
      expect(domain.allow_public_secret_creation?).to be(true)
    end
  end

  context 'when disabled' do
    it 'fails closed regardless of the stored mode' do
      stub_homepage_config(enabled: 'false', secrets_mode: 'create')
      expect(domain.allow_public_secret_creation?).to be(false)
    end
  end

  context 'when enabled in incoming mode' do
    it 'fails closed — visitors send secrets TO recipients, not create them' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'incoming')
      expect(domain.allow_public_secret_creation?).to be(false)
    end
  end

  context 'when the stored secrets_mode is corrupt/unrecognised' do
    it 'fails closed rather than falling open to the create form' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'corrupted-mode')
      expect(domain.allow_public_secret_creation?).to be(false)
    end
  end

  # Network rules narrow the "on" cell per visitor. The caller passes the
  # request's env['otto.ip_match'] closure as ip_match; the verdict is
  # HomepageConfig#network_allowed? (full matrix in
  # homepage_config_network_spec.rb). Here: the gate ANDs it in, a domain
  # without rules ignores it, and a domain with rules fails closed when
  # the caller cannot say where the request came from.
  context 'when the homepage carries network rules' do
    before { allow(OT).to receive(:le) }

    it 'authorizes a visitor inside an allowed range' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'create', allowed_cidrs: ['10.0.0.0/8'])
      expect(domain.allow_public_secret_creation?(ip_match: matcher_for('10.1.2.3'))).to be(true)
    end

    it 'refuses a visitor outside every allowed range' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'create', allowed_cidrs: ['10.0.0.0/8'])
      expect(domain.allow_public_secret_creation?(ip_match: matcher_for('192.168.1.1'))).to be(false)
    end

    it 'refuses a visitor inside a denied range even when the allow list admits them' do
      stub_homepage_config(
        enabled: 'true', secrets_mode: 'create',
        allowed_cidrs: ['10.0.0.0/8'], denied_cidrs: ['10.1.0.0/16'],
      )
      expect(domain.allow_public_secret_creation?(ip_match: matcher_for('10.1.2.3'))).to be(false)
    end

    it 'fails closed when the caller supplies no matcher' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'create', denied_cidrs: ['10.0.0.0/8'])
      expect(domain.allow_public_secret_creation?).to be(false)
    end

    it 'does not let network admission override the mode gate' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'incoming', allowed_cidrs: ['10.0.0.0/8'])
      expect(domain.allow_public_secret_creation?(ip_match: matcher_for('10.1.2.3'))).to be(false)
    end
  end

  context 'when the homepage carries no network rules' do
    it 'ignores the matcher entirely, including a nil one' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'create')
      expect(domain.allow_public_secret_creation?(ip_match: nil)).to be(true)
      expect(domain.allow_public_secret_creation?(ip_match: matcher_for('192.168.1.1'))).to be(true)
    end
  end
end
