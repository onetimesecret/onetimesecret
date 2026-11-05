# spec/unit/onetime/models/custom_domain/ownership_proven_spec.rb
#
# frozen_string_literal: true
#
# CustomDomain#ownership_proven?: whether a domain's accepted ownership rests
# on evidence, so tenant SSO may treat it as the organization's email
# namespace (#4734, RISK-2026-10-10-01). A Colonel override counts under any
# validation strategy. Otherwise the domain counts only under a strategy that
# checks the TXT record, and only when a passing check is on record
# (verified_confirmed_at, written by VerifyDomain for such a pass alone).
# ownership_verified by itself never counts: a passthrough pass or a
# pre-v0.26.14 verification sets it with no record, and a switch to a TXT
# strategy must not promote it (ADR-016, ADR-049). Serving
# (#serving_authorized?) is not affected. When the strategy cannot be built,
# both fail closed: serving requires ownership_verified and proof requires an
# override.
#
# Unsaved records and a per-example copy of OT.conf: no datastore or DNS I/O.
# The strategy switch is modelled with ConfirmationWindow, the object
# VerifyDomain#persist_changes writes the confirmation fields through.

require 'spec_helper'
require 'onetime/operations/verify_domain'

RSpec.describe Onetime::CustomDomain, '#ownership_proven?' do
  # An epoch a recorded TXT pass would carry.
  let(:recent_pass) { Time.now.to_i - 3600 }

  # features.domains settings for this example only, on a copy of OT.conf.
  # ownership_proof_required? decides again whenever the strategy differs.
  def configure_domains(**overrides)
    conf    = YAML.load(YAML.dump(OT.conf))
    domains = ((conf['features'] ||= {})['domains'] ||= {})
    overrides.each { |key, value| domains[key.to_s] = value }
    allow(OT).to receive(:conf).and_return(conf)
  end

  # confirmed: the verified_confirmed_at value; nil (the default) is a domain
  # with no TXT pass on record.
  def domain(verified:, override:, confirmed: nil)
    record                       = described_class.new(display_domain: 'secrets.acme-corp.example.com', org_id: 'org-proven-spec')
    record.ownership_verified    = verified
    record.verified_by_override  = override
    record.verified_confirmed_at = confirmed
    record
  end

  describe '#txt_pass_recorded?' do
    it 'is true for an epoch after zero' do
      expect(domain(verified: true, override: false, confirmed: recent_pass).txt_pass_recorded?).to be(true)
    end

    it 'is false for nil, an empty string and zero' do
      expect(domain(verified: true, override: false, confirmed: nil).txt_pass_recorded?).to be(false)
      expect(domain(verified: true, override: false, confirmed: '').txt_pass_recorded?).to be(false)
      expect(domain(verified: true, override: false, confirmed: 0).txt_pass_recorded?).to be(false)
    end
  end

  %w[approximated caddy_on_demand].each do |strategy|
    context "under #{strategy} (checks the TXT record)" do
      before { configure_domains(validation_strategy: strategy) }

      it 'checks the TXT record' do
        expect(described_class.ownership_proof_required?).to be(true)
        expect(described_class.ownership_proof_checked?).to be(true)
      end

      it 'counts a verified domain with a TXT pass on record' do
        expect(domain(verified: true, override: false, confirmed: recent_pass).ownership_proven?).to be(true)
      end

      it 'does not count a verified domain with no TXT pass on record' do
        expect(domain(verified: true, override: false, confirmed: nil).ownership_proven?).to be(false)
        expect(domain(verified: true, override: false, confirmed: '').ownership_proven?).to be(false)
        expect(domain(verified: true, override: false, confirmed: 0).ownership_proven?).to be(false)
      end

      it 'counts a Colonel override with no TXT pass on record' do
        expect(domain(verified: true, override: true, confirmed: nil).ownership_proven?).to be(true)
      end

      it 'counts a Colonel override with a TXT pass on record' do
        expect(domain(verified: true, override: true, confirmed: recent_pass).ownership_proven?).to be(true)
      end

      it 'does not count an override whose ownership was withdrawn' do
        expect(domain(verified: false, override: true).ownership_proven?).to be(false)
      end

      it 'does not count a recorded pass once ownership is withdrawn' do
        # A failing TXT check sets ownership_verified false and leaves the
        # old epoch in place; the flag is read first.
        expect(domain(verified: false, override: false, confirmed: recent_pass).ownership_proven?).to be(false)
      end

      it 'does not count a domain whose ownership is not verified' do
        expect(domain(verified: false, override: false).ownership_proven?).to be(false)
        expect(domain(verified: nil, override: nil).ownership_proven?).to be(false)
      end
    end
  end

  context 'under passthrough (makes no TXT check)' do
    before { configure_domains(validation_strategy: 'passthrough') }

    it 'does not check the TXT record' do
      expect(described_class.ownership_proof_required?).to be(false)
      expect(described_class.ownership_proof_checked?).to be(false)
    end

    it 'does not count a verified domain with no TXT pass on record' do
      expect(domain(verified: true, override: false, confirmed: nil).ownership_proven?).to be(false)
    end

    it 'does not count a verified domain with a TXT pass on record from an earlier strategy' do
      expect(domain(verified: true, override: false, confirmed: recent_pass).ownership_proven?).to be(false)
    end

    it 'counts a Colonel override' do
      expect(domain(verified: true, override: true, confirmed: nil).ownership_proven?).to be(true)
      expect(domain(verified: true, override: true, confirmed: recent_pass).ownership_proven?).to be(true)
    end

    it 'does not count an override whose ownership was withdrawn' do
      expect(domain(verified: false, override: true).ownership_proven?).to be(false)
    end

    it 'does not count a domain whose ownership is not verified' do
      expect(domain(verified: false, override: false).ownership_proven?).to be(false)
      expect(domain(verified: nil, override: nil).ownership_proven?).to be(false)
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

    it 'does not count a verified domain, with or without a TXT pass on record' do
      expect(domain(verified: true, override: false, confirmed: nil).ownership_proven?).to be(false)
      expect(domain(verified: true, override: false, confirmed: recent_pass).ownership_proven?).to be(false)
    end

    it 'counts a Colonel override' do
      expect(domain(verified: true, override: true).ownership_proven?).to be(true)
    end
  end

  # The case ADR-016 and ADR-049 describe: an install verifies a domain under
  # passthrough, then moves to a TXT strategy. The flag survives the switch
  # with no pass on record, and must not count until a check records one.
  context 'when the strategy is switched from passthrough to caddy_on_demand' do
    let(:now) { Time.now.to_i }
    let(:record) { domain(verified: false, override: false) }

    # What VerifyDomain#persist_changes writes for a passthrough pass: the
    # flag, and record_skipped on the window (no confirmation).
    def pass_under_passthrough!(record)
      result = { validated: true, mode: 'passthrough', message: 'External validation (passthrough mode)' }
      window = Onetime::Operations::VerifyDomain::ConfirmationWindow.new(record, result, now: now)
      record.ownership_verified = true
      window.record_skipped
    end

    # What it writes for a TXT pass under a strategy that proves ownership.
    def pass_under_txt_check!(record)
      result = { validated: true, data: { 'records' => [] }, mode: 'caddy_on_demand' }
      window = Onetime::Operations::VerifyDomain::ConfirmationWindow.new(record, result, now: now)
      record.ownership_verified = true
      window.record_settled(true, proven: true)
    end

    def switch_to_caddy_on_demand!
      configure_domains(validation_strategy: 'caddy_on_demand')
      expect(described_class.ownership_proof_checked?).to be(true)
    end

    before do
      configure_domains(validation_strategy: 'passthrough')
      pass_under_passthrough!(record)
    end

    it 'starts verified, with no TXT pass on record and not proven, under passthrough' do
      expect(record.ownership_verified).to be(true)
      expect(record.verified_confirmed_at).to be_nil
      expect(record.ownership_proven?).to be(false)
    end

    it 'is not proven after the switch, with no TXT pass on record' do
      switch_to_caddy_on_demand!

      expect(record.ownership_verified).to be(true)
      expect(record.ownership_proven?).to be(false)
    end

    it 'is still served after the switch' do
      switch_to_caddy_on_demand!

      expect(record.serving_authorized?).to be(true)
    end

    it 'is proven once a TXT check under the new strategy records a pass' do
      switch_to_caddy_on_demand!
      pass_under_txt_check!(record)

      expect(record.verified_confirmed_at).to eq(now)
      expect(record.ownership_proven?).to be(true)
    end

    it 'is proven at once when a Colonel overrides its verification' do
      switch_to_caddy_on_demand!
      record.verified_by_override = true

      expect(record.ownership_proven?).to be(true)
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
