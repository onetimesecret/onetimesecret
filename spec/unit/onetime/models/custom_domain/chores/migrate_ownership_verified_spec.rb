# spec/unit/onetime/models/custom_domain/chores/migrate_ownership_verified_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../../lib/onetime/models/custom_domain/chores/migrate_ownership_verified'

# Chore specs live with their model rather than under the Onetime::Chores namespace.
# rubocop:disable-next RSpec/SpecFilePathFormat
RSpec.describe Onetime::Chores::MigrateOwnershipVerified do
  subject(:chore) { described_class.new }

  let(:connection) { instance_double(Redis) }
  let(:domain) do
    instance_double(
      Onetime::CustomDomain,
      dbclient: connection,
      dbkey: 'custom_domain:test:object',
      extid: 'cd_test',
    )
  end
  let(:logger) { instance_double(SemanticLogger::Logger, info: nil) }

  before do
    allow(Onetime).to receive(:get_logger).with('Chores').and_return(logger)
  end

  it 'is registered on CustomDomain' do
    expect(Onetime::CustomDomain.chores[:migrate_ownership_verified]).to be_a(described_class)
  end

  context 'when the script copies legacy ownership' do
    before do
      allow(connection).to receive(:eval).and_return(1)
    end

    it 'reports a modification' do
      expect(chore.call(domain)).to be(true)
    end

    it 'runs the atomic copy script against the domain object key' do
      chore.call(domain)

      expect(connection).to have_received(:eval)
        .with(described_class::COPY_LUA, keys: ['custom_domain:test:object']).once
    end

    it 'logs the copy with the chore and domain identifiers' do
      chore.call(domain)

      expect(logger).to have_received(:info).with(
        'Copied legacy ownership verification',
        chore: :migrate_ownership_verified,
        domain_extid: 'cd_test',
      ).once
    end
  end

  it 'silently reports no modification when the script skips the record' do
    allow(connection).to receive(:eval).and_return(0)
    result = chore.call(domain)

    aggregate_failures do
      expect(result).to be(false)
      expect(logger).not_to have_received(:info)
    end
  end

  it 'propagates datastore failures for housekeeping error counting' do
    allow(connection).to receive(:eval).and_raise(Redis::CannotConnectError)
    expect { chore.call(domain) }.to raise_error(Redis::CannotConnectError)
  end
end
