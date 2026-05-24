# spec/unit/onetime/models/custom_domain/chores/migrate_incoming_secrets_to_config_spec.rb
#
# frozen_string_literal: true

# Unit tests for the migrate_incoming_secrets_to_config housekeeping chore.
#
# Mirrors the conventions established by
# spec/unit/onetime/models/organization/chores/standardize_planid_spec.rb:
# fully mocked — no Redis, no real CustomDomain / IncomingConfig instances —
# so the test only exercises the chore body's branching, logging, and
# return-value contract.
#
# Run: pnpm run test:rspec spec/unit/onetime/models/custom_domain/chores/migrate_incoming_secrets_to_config_spec.rb

require 'spec_helper'

# Load the chore registration
require_relative '../../../../../../lib/onetime/models/custom_domain/chores/migrate_incoming_secrets_to_config'

RSpec.describe 'CustomDomain chore: migrate_incoming_secrets_to_config' do
  let(:chore) { Onetime::CustomDomain.chores[:migrate_incoming_secrets_to_config] }
  let(:chore_name) { :migrate_incoming_secrets_to_config }

  # SemanticLogger double accepting (message, **kwargs) signature.
  let(:mock_logger) do
    double('SemanticLogger').tap do |logger|
      allow(logger).to receive(:info) { |_msg, _payload = {}| nil }
    end
  end

  # Defaults; individual contexts override via `let`.
  let(:domain_extid) { 'dom_test_extid_abc' }
  let(:domain_identifier) { 'dom_test_id_xyz' }
  let(:legacy_json) { nil }
  let(:incoming_secrets_value) do
    legacy_json.nil? ? nil : double('JsonStringKey', value: legacy_json)
  end

  let(:domain) do
    instance_double(
      'Onetime::CustomDomain',
      extid: domain_extid,
      identifier: domain_identifier,
      incoming_secrets: incoming_secrets_value,
    )
  end

  before do
    allow(Onetime).to receive(:get_logger).with('Chores').and_return(mock_logger)
    # Default: no existing IncomingConfig record. Individual contexts may override.
    allow(Onetime::CustomDomain::IncomingConfig)
      .to receive(:find_by_domain_id).with(domain_identifier).and_return(nil)
  end

  describe 'chore registration' do
    it 'is registered on Onetime::CustomDomain' do
      expect(Onetime::CustomDomain.chores).to have_key(chore_name)
    end

    it 'is a callable block' do
      expect(chore).to respond_to(:call)
    end
  end

  describe 'no legacy blob (silent skip)' do
    context 'when incoming_secrets accessor returns nil' do
      let(:incoming_secrets_value) { nil }

      it 'returns nil' do
        expect(chore.call(domain)).to be_nil
      end

      it 'does not log' do
        expect(mock_logger).not_to receive(:info)
        chore.call(domain)
      end

      it 'does not create an IncomingConfig' do
        expect(Onetime::CustomDomain::IncomingConfig).not_to receive(:create!)
        chore.call(domain)
      end
    end

    context 'when incoming_secrets.value is nil' do
      let(:legacy_json) { nil }
      let(:incoming_secrets_value) { double('JsonStringKey', value: nil) }

      it 'returns nil and does not log' do
        expect(mock_logger).not_to receive(:info)
        expect(chore.call(domain)).to be_nil
      end
    end

    context 'when incoming_secrets.value is an empty string' do
      let(:legacy_json) { '' }

      it 'returns nil and does not log' do
        expect(mock_logger).not_to receive(:info)
        expect(chore.call(domain)).to be_nil
      end
    end
  end

  describe 'corrupted JSON (log + skip)' do
    context 'when blob is not valid JSON' do
      let(:legacy_json) { 'not-json-at-all' }

      it 'returns nil (does not raise)' do
        expect { chore.call(domain) }.not_to raise_error
        expect(chore.call(domain)).to be_nil
      end

      it 'logs the failure with chore + domain_extid + error' do
        expect(mock_logger).to receive(:info).with(
          'Migration failed: corrupted legacy blob',
          hash_including(
            chore: chore_name,
            domain_extid: domain_extid,
            error: kind_of(String),
          ),
        )
        chore.call(domain)
      end

      it 'does not call IncomingConfig.create!' do
        expect(Onetime::CustomDomain::IncomingConfig).not_to receive(:create!)
        chore.call(domain)
      end
    end
  end

  describe 'empty recipients (log + skip)' do
    shared_examples 'logs empty-blob skip' do
      it 'logs the skip with chore + domain_extid' do
        expect(mock_logger).to receive(:info).with(
          'Skipping empty legacy blob',
          hash_including(chore: chore_name, domain_extid: domain_extid),
        )
        chore.call(domain)
      end

      it 'returns nil' do
        expect(chore.call(domain)).to be_nil
      end

      it 'does not call IncomingConfig.create!' do
        expect(Onetime::CustomDomain::IncomingConfig).not_to receive(:create!)
        chore.call(domain)
      end
    end

    context 'when recipients key is missing' do
      let(:legacy_json) { '{"memo_max_length":50,"default_ttl":604800}' }
      include_examples 'logs empty-blob skip'
    end

    context 'when recipients is an empty array' do
      let(:legacy_json) { '{"recipients":[]}' }
      include_examples 'logs empty-blob skip'
    end

    context 'when recipients is not an array (corrupted shape)' do
      let(:legacy_json) { '{"recipients":"oops"}' }
      include_examples 'logs empty-blob skip'
    end

    context 'when parsed value is not a hash at all (e.g. JSON array)' do
      let(:legacy_json) { '[]' }
      include_examples 'logs empty-blob skip'
    end
  end

  describe 'already migrated (log + skip, no overwrite)' do
    let(:legacy_json) do
      '{"recipients":[{"email":"a@example.com","name":"A"}]}'
    end

    before do
      existing = instance_double('Onetime::CustomDomain::IncomingConfig')
      allow(Onetime::CustomDomain::IncomingConfig)
        .to receive(:find_by_domain_id).with(domain_identifier).and_return(existing)
    end

    it 'logs the skip with chore + domain_extid' do
      expect(mock_logger).to receive(:info).with(
        'Skipping (already migrated)',
        hash_including(chore: chore_name, domain_extid: domain_extid),
      )
      chore.call(domain)
    end

    it 'does not call IncomingConfig.create!' do
      expect(Onetime::CustomDomain::IncomingConfig).not_to receive(:create!)
      chore.call(domain)
    end

    it 'returns nil' do
      expect(chore.call(domain)).to be_nil
    end
  end

  describe 'successful migration' do
    let(:recipients_payload) do
      [
        { 'email' => 'support@example.com', 'name' => 'Support' },
        { 'email' => 'admin@example.com',   'name' => 'Admin' },
      ]
    end
    let(:legacy_json) { JSON.generate('recipients' => recipients_payload) }

    before do
      allow(Onetime::CustomDomain::IncomingConfig).to receive(:create!).and_return(
        instance_double('Onetime::CustomDomain::IncomingConfig'),
      )
    end

    it 'creates an IncomingConfig with enabled: true and the legacy recipients' do
      expect(Onetime::CustomDomain::IncomingConfig).to receive(:create!).with(
        domain_id: domain_identifier,
        enabled: true,
        recipients: recipients_payload,
      )
      chore.call(domain)
    end

    it 'logs the migration with recipients_count' do
      expect(mock_logger).to receive(:info).with(
        'Migrated incoming recipients',
        hash_including(
          chore: chore_name,
          domain_extid: domain_extid,
          recipients_count: recipients_payload.size,
        ),
      )
      chore.call(domain)
    end

    it 'returns true so HousekeepingJob counts it as modified' do
      expect(chore.call(domain)).to be true
    end

    context 'with a single recipient' do
      let(:recipients_payload) { [{ 'email' => 'solo@example.com', 'name' => 'Solo' }] }

      it 'creates with one recipient' do
        expect(Onetime::CustomDomain::IncomingConfig).to receive(:create!).with(
          hash_including(recipients: [{ 'email' => 'solo@example.com', 'name' => 'Solo' }]),
        )
        chore.call(domain)
      end

      it 'logs recipients_count: 1' do
        expect(mock_logger).to receive(:info).with(
          'Migrated incoming recipients',
          hash_including(recipients_count: 1),
        )
        chore.call(domain)
      end
    end

    context 'when legacy blob has extra unrelated keys' do
      let(:legacy_json) do
        JSON.generate(
          'recipients' => recipients_payload,
          'memo_max_length' => 50,
          'default_ttl' => 604_800,
        )
      end

      it 'still migrates only the recipients (ignores memo/ttl)' do
        expect(Onetime::CustomDomain::IncomingConfig).to receive(:create!).with(
          hash_including(recipients: recipients_payload),
        )
        chore.call(domain)
      end
    end
  end

  describe 'create! failure (log + skip, no raise)' do
    let(:legacy_json) do
      '{"recipients":[{"email":"bad@example","name":"Invalid"}]}'
    end

    before do
      allow(Onetime::CustomDomain::IncomingConfig)
        .to receive(:create!).and_raise(Onetime::Problem, 'Invalid email format: bad@example')
    end

    it 'does not raise' do
      expect { chore.call(domain) }.not_to raise_error
    end

    it 'logs the failure with chore + domain_extid + error' do
      expect(mock_logger).to receive(:info).with(
        'Migration failed',
        hash_including(
          chore: chore_name,
          domain_extid: domain_extid,
          error: 'Invalid email format: bad@example',
        ),
      )
      chore.call(domain)
    end

    it 'returns nil so HousekeepingJob does not count it as modified' do
      expect(chore.call(domain)).to be_nil
    end
  end

  describe 'unexpected exceptions (propagate to HousekeepingJob)' do
    let(:legacy_json) { '{"recipients":[{"email":"x@example.com","name":"X"}]}' }

    before do
      allow(Onetime::CustomDomain::IncomingConfig)
        .to receive(:create!).and_raise(RuntimeError, 'redis down')
    end

    # The housekeeping job rescues StandardError per-record and counts the error;
    # the chore deliberately does NOT swallow non-domain exceptions so unexpected
    # failures surface in the run stats.
    it 'allows non-Onetime::Problem exceptions to propagate' do
      expect { chore.call(domain) }.to raise_error(RuntimeError, 'redis down')
    end
  end

  describe 'idempotency contract' do
    # Documents the full happy-path-then-rerun cycle by composing the
    # individual context behaviors. First call creates; second call hits the
    # already-migrated branch.
    let(:legacy_json) do
      '{"recipients":[{"email":"once@example.com","name":"Once"}]}'
    end

    it 'first call creates, second call skips' do
      created_record = instance_double('Onetime::CustomDomain::IncomingConfig')

      # First invocation: no existing record -> create
      expect(Onetime::CustomDomain::IncomingConfig)
        .to receive(:find_by_domain_id).with(domain_identifier).and_return(nil, created_record)
      expect(Onetime::CustomDomain::IncomingConfig).to receive(:create!).once.and_return(created_record)

      first_result = chore.call(domain)
      second_result = chore.call(domain)

      expect(first_result).to be true
      expect(second_result).to be_nil
    end
  end
end
