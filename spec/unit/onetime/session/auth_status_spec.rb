# spec/unit/onetime/session/auth_status_spec.rb
#
# frozen_string_literal: true

# `auth_status` is the public projection of a customer-session verdict on the
# bootstrap payload (#4462). Every mapping may only withhold.

require 'spec_helper'
require 'onetime/session/auth_status'

RSpec.describe Onetime::SessionAuthStatus do
  let(:evaluator) { Onetime::CustomerSessionEvaluator }

  def verdict(status, reason)
    identity = status == :authenticated ? { principal: :principal, customer: :customer } : {}
    evaluator::Verdict.new(status: status, reason: reason, **identity)
  end

  it 'sends four values; checking is client-only' do
    expect(described_class::VALUES).to contain_exactly('authenticated', 'anonymous', 'mfa_pending', 'unavailable')
  end

  it 'maps every evaluator status' do
    expect(described_class::BY_VERDICT_STATUS.keys).to match_array(evaluator::STATUSES)
  end

  it 'yields authenticated only for an authenticated verdict' do
    granting = described_class::BY_VERDICT_STATUS.select { |_status, value| value == 'authenticated' }

    expect(granting.keys).to eq([:authenticated])
  end

  it 'reports a rejected session as anonymous, without its reason' do
    (Onetime::CustomerSessionEvaluator::REASONS - [:authenticated]).each do |reason|
      status = described_class.for_verdict(verdict(:rejected, reason))

      expect(status).to eq('anonymous')
    end
  end

  it 'keeps an outage distinct from a sign-out' do
    expect(described_class.for_verdict(verdict(:unavailable, :customer_unavailable))).to eq('unavailable')
    expect(described_class.for_verdict(verdict(:unavailable, :active_session_unavailable))).to eq('unavailable')
  end

  it 'projects MFA-pending and authenticated verdicts' do
    expect(described_class.for_verdict(verdict(:mfa_pending, :awaiting_mfa))).to eq('mfa_pending')
    expect(described_class.for_verdict(verdict(:authenticated, :authenticated))).to eq('authenticated')
  end

  describe '.without_verdict (error-recovery render, evaluator not run)' do
    it 'is unavailable when the raw session names a customer' do
      expect(described_class.without_verdict({ 'external_id' => 'ur_alice' })).to eq('unavailable')
    end

    it 'is anonymous otherwise' do
      [nil, {}, { 'external_id' => nil }, { 'external_id' => '' }, 'not a session'].each do |session|
        expect(described_class.without_verdict(session)).to eq('anonymous')
      end
    end

    it 'never answers authenticated, whatever the session claims' do
      session = { 'external_id' => 'ur_alice', 'authenticated' => true }

      expect(described_class.without_verdict(session)).not_to eq('authenticated')
    end
  end

  describe 'parity with src/schemas/contracts/bootstrap.ts' do
    it 'lists the same values' do
      source = File.read(File.join(Onetime::HOME, 'src/schemas/contracts/bootstrap.ts'))
      values = source[/export const authStatusValues = \[(.*?)\] as const/m, 1].scan(/'(\w+)'/).flatten

      expect(values).to match_array(described_class::VALUES)
    end
  end
end
