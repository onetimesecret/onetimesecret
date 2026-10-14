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

  let!(:config) { create_config }

  def create_config
    # Credentials are irrelevant to the persisted config/outcome lifecycle.
    allow_any_instance_of(Onetime::CustomDomain::SsoConfig).to receive(:valid?).and_return(true)
    Onetime::CustomDomain::SsoConfig.create!(domain_id: domain_id)
  end

  after do
    described_class.new(domain_id: domain_id).destroy!
    Onetime::CustomDomain::SsoConfig.delete_for_domain!(domain_id)
  end

  describe '.record_success!' do
    it 'creates the record with result, timestamps and provider type' do
      allow(described_class).to receive(:log_write_failure) { |_method, _domain, error| raise error }
      outcome = described_class.record_success!(domain_id, config: config, provider_type: 'entra_id', now: now)

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
      described_class.record_success!(domain_id, config: config, provider_type: 'oidc', now: now)

      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(result: 'succeeded', at: now.to_i)
    end

    it 'sets a TTL of OUTCOME_TTL and renews it on every write' do
      first = described_class.record_success!(domain_id, config: config, now: now)
      expect(first.ttl).to be_between(described_class::OUTCOME_TTL - 60, described_class::OUTCOME_TTL)

      first.update_expiration(expiration: 60)
      described_class.record_failure!(domain_id, config: config, stage: 'provider', code: 'timeout')
      expect(described_class.find_by_domain_id(domain_id).ttl).to be > 60
    end

    it 'keeps the last failure when a later success is recorded' do
      described_class.record_failure!(domain_id, config: config, stage: 'provider', code: 'invalid_credentials', now: now - 60)
      described_class.record_success!(domain_id, config: config, now: now)

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

      expect(described_class.record_success!(domain_id, config: config)).to be_nil
      expect(OT).to have_received(:le).with(a_string_including('record_success!', 'Redis::BaseConnectionError'))
    end
  end

  describe '.record_failure!' do
    it 'creates the record with the stage and sanitized code' do
      outcome = described_class.record_failure!(
        domain_id, config: config, stage: :callback, code: :domain_not_allowed, provider_type: 'oidc', now: now,
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
      described_class.record_success!(domain_id, config: config, provider_type: 'entra_id', now: now - 3600)
      described_class.record_failure!(domain_id, config: config, stage: 'provider', code: 'invalid_credentials', now: now)

      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(
        result: 'failed',
        succeeded_at: now.to_i - 3600,
        failed_at: now.to_i,
        failure_code: 'invalid_credentials',
        provider_type: 'entra_id',
      )
    end

    it 'keeps the last known provider type when a write has none' do
      described_class.record_success!(domain_id, config: config, provider_type: 'saml', now: now)
      described_class.record_failure!(domain_id, config: config, stage: 'provider', code: 'invalid_ticket', now: now)

      expect(described_class.find_by_domain_id(domain_id).last_provider_type).to eq('saml')
    end

    it 'refuses an unknown stage' do
      expect(described_class.record_failure!(domain_id, config: config, stage: 'idp', code: 'x')).to be_nil
      expect(described_class.find_by_domain_id(domain_id)).to be_nil
    end

    # The provider-stage code is OmniAuth's error type, which for the OAuth2
    # family is the IdP's `error` parameter: unauthenticated-client-shaped.
    it 'stores only a sanitized, bounded code' do
      outcome = described_class.record_failure!(
        domain_id, config: config, stage: 'provider', code: "Bad Thing <script>\n#{'x' * 100}", now: now,
      )

      code = outcome.last_failure_code
      expect(code).to match(described_class::CODE_FORMAT)
      expect(code.length).to eq(described_class::CODE_MAX)
      expect(code).to start_with('bad_thing__script__')
    end
  end

  describe 'F1: concurrent and out-of-order outcomes' do
    it 'retains a success committed while a failure writer is in flight' do
      described_class.record_success!(domain_id, config: config, now: now - 60)
      interleaved = false
      allow(described_class).to receive(:find_by_domain_id).and_wrap_original do |original, *args, **kwargs|
        snapshot = original.call(*args, **kwargs)
        unless interleaved
          interleaved = true
          described_class.record_success!(domain_id, config: config, now: now)
        end
        snapshot
      end

      described_class.record_failure!(domain_id, config: config, stage: 'provider', code: 'timeout', now: now + 1)
      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(
        succeeded_at: now.to_i, failed_at: now.to_i + 1,
      )
    end

    it 'merges overlapping writers at the atomic update boundary without losing either result' do
      client = described_class.new(domain_id: domain_id).dbclient
      allow_any_instance_of(described_class).to receive(:dbclient).and_return(client)
      waiting = Queue.new
      release = Queue.new
      allow(client).to receive(:eval).and_wrap_original do |original, script, **kwargs|
        if script == described_class::WRITE_SCRIPT && kwargs[:argv][6] == 'succeeded'
          waiting << true
          release.pop
        end
        result = original.call(script, **kwargs)
        if script == described_class::WRITE_SCRIPT
          expect(client.ttl(kwargs[:keys].first)).to be > 60
        end
        result
      end

      writer = Thread.new { described_class.record_success!(domain_id, config: config, now: now) }
      Timeout.timeout(5) { waiting.pop }
      described_class.record_failure!(domain_id, config: config, stage: 'provider', code: 'timeout', now: now + 1)
      release << true
      expect(Timeout.timeout(5) { writer.value }).not_to be_nil
      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(
        result: 'failed', at: now.to_i + 1, succeeded_at: now.to_i, failed_at: now.to_i + 1,
      )
    ensure
      writer&.kill if writer&.alive?
      writer&.join
    end

    it 'orders subsecond events and uses execution order for exact ties' do
      described_class.record_success!(domain_id, config: config, now: now + 0.9, provider_type: 'oidc')
      described_class.record_failure!(domain_id, config: config, stage: 'provider', code: 'timeout', now: now + 0.1, provider_type: 'saml')
      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(result: 'succeeded', provider_type: 'oidc')

      described_class.record_failure!(domain_id, config: config, stage: 'account', code: 'missing_email', now: now + 0.9)
      described_class.record_success!(domain_id, config: config, now: now - 1)
      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(
        result: 'failed', succeeded_at: now.to_i, failure_code: 'missing_email',
      )
    end

    it 'does not regress the last result or the latest failure details on a late write' do
      described_class.record_failure!(domain_id, config: config, stage: 'account', code: 'missing_email', now: now)
      described_class.record_success!(domain_id, config: config, now: now + 1)
      described_class.record_failure!(domain_id, config: config, stage: 'provider', code: 'timeout', now: now - 1)

      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(
        result: 'succeeded', at: now.to_i + 1, failed_at: now.to_i,
        failure_stage: 'account', failure_code: 'missing_email',
      )
    end
  end

  describe 'F2: config replacement' do
    it 'does not expose a late callback from the deleted config on its replacement' do
      captured_config = config
      Onetime::CustomDomain::SsoConfig.delete_for_domain!(domain_id)
      described_class.delete_for_domain!(domain_id, config: captured_config)
      expect(described_class.record_success!(domain_id, config: captured_config, now: now)).to be_nil
      create_config

      expect(described_class.find_by_domain_id(domain_id)).to be_nil
    end

    it 'rejects old writes and delayed cleanup after the replacement has its own history' do
      allow(Familia).to receive(:now).and_return(config.created)
      Onetime::CustomDomain::SsoConfig.delete_for_domain!(domain_id)
      replacement = create_config
      expect(replacement.created).to eq(config.created)
      expect(replacement.outcome_generation).not_to eq(config.outcome_generation)
      described_class.record_success!(domain_id, config: replacement, now: now)

      expect(described_class.record_failure!(domain_id, config: config, stage: 'provider', code: 'timeout', now: now + 1)).to be_nil
      expect(described_class.delete_for_domain!(domain_id, config: config)).to be false
      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(result: 'succeeded', failed_at: nil)
    end

    it 'checks the live config inside the atomic write, not before it' do
      client = described_class.new(domain_id: domain_id).dbclient
      allow_any_instance_of(described_class).to receive(:dbclient).and_return(client)
      allow(client).to receive(:eval).and_wrap_original do |original, script, **kwargs|
        Onetime::CustomDomain::SsoConfig.delete_for_domain!(domain_id) if script == described_class::WRITE_SCRIPT
        original.call(script, **kwargs)
      end

      expect(described_class.record_success!(domain_id, config: config, now: now)).to be_nil
      expect(described_class.load(domain_id)).to be_nil
    end

    it 'requires a captured config and refuses a config from another domain' do
      expect(described_class.record_success!(domain_id)).to be_nil
      expect(described_class.record_success!('another-domain', config: config)).to be_nil
      expect(described_class.load(domain_id)).to be_nil
    end

    it 'keeps history through ordinary config edits' do
      described_class.record_success!(domain_id, config: config, now: now)
      config.display_name = 'Renamed'
      config.save

      reloaded = Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain_id)
      expect(reloaded.outcome_generation).to eq(config.outcome_generation)
      expect(described_class.find_by_domain_id(domain_id, config: reloaded).succeeded?).to be true
    end

    it 'supports legacy configs without mutating them and rejects their callbacks after replacement' do
      config.dbclient.hdel(config.dbkey, 'outcome_generation')
      legacy = Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain_id)
      before = config.dbclient.hgetall(config.dbkey)
      expect(described_class.record_success!(domain_id, config: legacy, now: now)).not_to be_nil
      expect(described_class.find_by_domain_id(domain_id).succeeded?).to be true
      expect(config.dbclient.hgetall(config.dbkey)).to eq(before)

      Onetime::CustomDomain::SsoConfig.delete_for_domain!(domain_id)
      create_config
      expect(described_class.find_by_domain_id(domain_id)).to be_nil
      expect(described_class.record_success!(domain_id, config: legacy, now: now + 1)).to be_nil
    end

    it 'ignores unbound legacy outcomes rather than assigning them to the current config' do
      described_class.new(domain_id: domain_id, last_result: 'succeeded', last_at: now.to_i).save
      expect(described_class.find_by_domain_id(domain_id)).to be_nil
      described_class.record_failure!(domain_id, config: config, stage: 'provider', code: 'timeout', now: now)
      expect(described_class.find_by_domain_id(domain_id).to_api_h).to include(result: 'failed', succeeded_at: nil)
    end

    it 'does not expose leftover history if outcome cleanup failed' do
      described_class.record_success!(domain_id, config: config, now: now)
      Onetime::CustomDomain::SsoConfig.delete_for_domain!(domain_id)
      # Outcome cleanup failed: leave the old key in place.
      create_config

      expect(described_class.find_by_domain_id(domain_id)).to be_nil
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
      described_class.record_success!(domain_id, config: config)

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
