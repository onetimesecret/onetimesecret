# spec/unit/onetime/models/custom_domain/sso_signin_outcome_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# CustomDomain::SsoSigninOutcome — the last tenant SSO sign-in outcome per
# domain, written by the tenant SSO hooks and served to the domain owner as
# `record.last_sign_in`. Outcomes only: no identity, no IdP text; the code
# is sanitized before storage. Best-effort writers; TTL renewed per write.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only spec/unit/onetime/models/custom_domain/sso_signin_outcome_spec.rb
RSpec.describe Onetime::CustomDomain::SsoSigninOutcome do
  let(:domain_id) { "outcome-spec-#{SecureRandom.hex(6)}" }
  let(:now) { Time.at(1_760_000_000) }

  after { described_class.delete_for_domain!(domain_id) }

  describe '.record_success!' do
    it 'creates the record with result, timestamps and provider type' do
      outcome = described_class.record_success!(domain_id, provider_type: 'entra_id', now: now)

      expect(outcome).to be_a(described_class)
      expect(outcome.succeeded?).to be true
      expect(outcome.to_api_h).to eq(
        result: 'succeeded',
        at: now.to_i,
        succeeded_at: now.to_i,
        failed_at: nil,
        failure_stage: nil,
        failure_code: nil,
        provider_type: 'entra_id',
      )
    end

    it 'persists so the domain settings read finds it' do
      described_class.record_success!(domain_id, provider_type: 'oidc', now: now)

      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(result: 'succeeded', at: now.to_i)
    end

    it 'sets a TTL of OUTCOME_TTL and renews it on every write' do
      first = described_class.record_success!(domain_id, now: now)
      expect(first.ttl).to be_between(described_class::OUTCOME_TTL - 60, described_class::OUTCOME_TTL)

      first.update_expiration(expiration: 60)
      described_class.record_failure!(domain_id, stage: 'provider', code: 'timeout')
      expect(described_class.find_by_domain_id(domain_id).ttl).to be > 60
    end

    it 'keeps the last failure when a later success is recorded' do
      described_class.record_failure!(domain_id, stage: 'provider', code: 'invalid_credentials', now: now - 60)
      described_class.record_success!(domain_id, now: now)

      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(
        result: 'succeeded',
        at: now.to_i,
        succeeded_at: now.to_i,
        failed_at: now.to_i - 60,
        failure_stage: 'provider',
        failure_code: 'invalid_credentials',
      )
    end

    it 'records nothing for a blank domain id' do
      expect(described_class.record_success!('')).to be_nil
      expect(described_class.record_success!(nil)).to be_nil
    end

    it 'is best-effort: a write error is logged and returns nil, never raises' do
      allow(described_class).to receive(:write).and_raise(Redis::BaseConnectionError, 'down')
      allow(OT).to receive(:le)

      expect(described_class.record_success!(domain_id)).to be_nil
      expect(OT).to have_received(:le).with(a_string_including('record_success!', 'Redis::BaseConnectionError'))
    end
  end

  describe '.record_failure!' do
    it 'creates the record with the stage and sanitized code' do
      outcome = described_class.record_failure!(
        domain_id, stage: :callback, code: :domain_not_allowed, provider_type: 'oidc', now: now,
      )

      expect(outcome.failed?).to be true
      expect(outcome.to_api_h).to eq(
        result: 'failed',
        at: now.to_i,
        succeeded_at: nil,
        failed_at: now.to_i,
        failure_stage: 'callback',
        failure_code: 'domain_not_allowed',
        provider_type: 'oidc',
      )
    end

    it 'keeps the last success when a later failure is recorded' do
      described_class.record_success!(domain_id, provider_type: 'entra_id', now: now - 3600)
      described_class.record_failure!(domain_id, stage: 'provider', code: 'invalid_credentials', now: now)

      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(
        result: 'failed',
        succeeded_at: now.to_i - 3600,
        failed_at: now.to_i,
        failure_code: 'invalid_credentials',
        provider_type: 'entra_id',
      )
    end

    it 'keeps the last known provider type when a write has none' do
      described_class.record_success!(domain_id, provider_type: 'saml', now: now)
      described_class.record_failure!(domain_id, stage: 'provider', code: 'invalid_ticket', now: now)

      expect(described_class.find_by_domain_id(domain_id).last_provider_type).to eq('saml')
    end

    it 'refuses an unknown stage' do
      expect(described_class.record_failure!(domain_id, stage: 'idp', code: 'x')).to be_nil
      expect(described_class.find_by_domain_id(domain_id)).to be_nil
    end

    # The provider-stage code is OmniAuth's error type, which for the OAuth2
    # family is the IdP's `error` parameter: unauthenticated-client-shaped.
    it 'stores only a sanitized, bounded code' do
      outcome = described_class.record_failure!(
        domain_id, stage: 'provider', code: "Bad Thing <script>\n#{'x' * 100}", now: now,
      )

      code = outcome.last_failure_code
      expect(code).to match(described_class::CODE_FORMAT)
      expect(code.length).to eq(described_class::CODE_MAX)
      expect(code).to start_with('bad_thing__script__')
    end
  end

  describe '.sanitize_code' do
    it 'lowercases and keeps [a-z0-9_.-]' do
      expect(described_class.sanitize_code('Invalid_Credentials')).to eq('invalid_credentials')
      expect(described_class.sanitize_code('access-denied.v2')).to eq('access-denied.v2')
    end

    it 'replaces every other character' do
      expect(described_class.sanitize_code('a b/c:d')).to eq('a_b_c_d')
    end

    it 'substitutes a fixed word for a blank code' do
      expect(described_class.sanitize_code(nil)).to eq('unknown')
      expect(described_class.sanitize_code('')).to eq('unknown')
    end

    it 'scrubs invalid encoding rather than raising' do
      expect(described_class.sanitize_code("ok\xff".dup.force_encoding('UTF-8'))).to eq('ok_')
    end

    it 'is idempotent on its own output' do
      once = described_class.sanitize_code("Weird Code!\t#{'y' * 80}")
      expect(described_class.sanitize_code(once)).to eq(once)
    end
  end

  describe '.delete_for_domain!' do
    it 'removes the record and reports whether one existed' do
      described_class.record_success!(domain_id)

      expect(described_class.delete_for_domain!(domain_id)).to be true
      expect(described_class.find_by_domain_id(domain_id)).to be_nil
      expect(described_class.delete_for_domain!(domain_id)).to be false
    end
  end

  describe '#to_api_h' do
    it 'serves nil for unset fields and integers for timestamps' do
      outcome = described_class.new(domain_id: domain_id, last_result: 'failed', last_at: '1760000000')

      expect(outcome.to_api_h).to eq(
        result: 'failed', at: 1_760_000_000, succeeded_at: nil, failed_at: nil,
        failure_stage: nil, failure_code: nil, provider_type: nil,
      )
    end
  end
end
