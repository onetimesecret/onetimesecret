# spec/unit/onetime/models/custom_domain/ownership_proven_spec.rb
#
# frozen_string_literal: true
#
# CustomDomain#ownership_proven?: whether a domain's accepted ownership rests
# on evidence, so tenant SSO may treat it as the organization's email
# namespace (#4734, RISK-2026-10-10-01). A Colonel override counts under any
# validation strategy; ownership_verified alone counts only under a strategy
# that checks the TXT record. Serving (#serving_authorized?) is not affected.
# When the strategy cannot be built, both fail closed: serving requires
# ownership_verified and proof requires an override.
#
# Unsaved records and a per-example copy of OT.conf: no datastore or DNS I/O.

require 'spec_helper'

RSpec.describe Onetime::CustomDomain, '#ownership_proven?' do
  # features.domains settings for this example only, on a copy of OT.conf.
  # ownership_proof_required? decides again whenever the strategy differs.
  def configure_domains(**overrides)
    conf    = YAML.load(YAML.dump(OT.conf))
    domains = ((conf['features'] ||= {})['domains'] ||= {})
    overrides.each { |key, value| domains[key.to_s] = value }
    allow(OT).to receive(:conf).and_return(conf)
  end

  def domain(verified:, override:)
    record                      = described_class.new(display_domain: 'secrets.acme-corp.example.com', org_id: 'org-proven-spec')
    record.ownership_verified   = verified
    record.verified_by_override = override
    record
  end

  {
    'passthrough' => false,
    'approximated' => true,
    'caddy_on_demand' => true,
  }.each do |strategy, checks_txt|
    context "under #{strategy}" do
      before { configure_domains(validation_strategy: strategy) }

      it "#{checks_txt ? 'checks' : 'does not check'} the TXT record" do
        expect(described_class.ownership_proof_required?).to be(checks_txt)
        expect(described_class.ownership_proof_checked?).to be(checks_txt)
      end

      it "#{checks_txt ? 'counts' : 'does not count'} ownership_verified without an override" do
        expect(domain(verified: true, override: false).ownership_proven?).to be(checks_txt)
      end

      it 'counts ownership_verified with a Colonel override' do
        expect(domain(verified: true, override: true).ownership_proven?).to be(true)
      end

      it 'does not count an override whose ownership was withdrawn' do
        expect(domain(verified: false, override: true).ownership_proven?).to be(false)
      end

      it 'does not count a domain whose ownership is not verified' do
        expect(domain(verified: false, override: false).ownership_proven?).to be(false)
        expect(domain(verified: nil, override: nil).ownership_proven?).to be(false)
      end
    end
  end

  # Strategy.for_config raises for an unknown name under strict_strategy.
  # Serving then fails closed (ownership_verified required) and proof fails
  # closed too (only an override counts), even though both read the same
  # failed decision.
  context 'under a strategy that cannot be built' do
    before do
      allow(OT).to receive(:le)
      configure_domains(validation_strategy: 'bogus', strict_strategy: true)
    end

    it 'reports the strategy as unbuildable' do
      expect(described_class.validation_strategy_state).to eq(:unbuildable)
      expect(described_class.ownership_proof_checked?).to be(false)
    end

    it 'still requires ownership_verified for serving' do
      expect(described_class.ownership_proof_required?).to be(true)
      expect(domain(verified: false, override: false).serving_authorized?).to be(false)
      expect(domain(verified: true, override: false).serving_authorized?).to be(true)
    end

    it 'does not count ownership_verified without an override' do
      expect(domain(verified: true, override: false).ownership_proven?).to be(false)
    end

    it 'counts ownership_verified with a Colonel override' do
      expect(domain(verified: true, override: true).ownership_proven?).to be(true)
    end
  end

  context 'beside serving under passthrough' do
    before { configure_domains(validation_strategy: 'passthrough') }

    it 'still serves a registered domain that does not prove its email namespace' do
      record = domain(verified: true, override: false)

      expect(record.serving_authorized?).to be(true)
      expect(record.ownership_proven?).to be(false)
    end
  end
end
