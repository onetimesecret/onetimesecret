# apps/web/auth/spec/unit/migrator_spec.rb
#
# frozen_string_literal: true

# The migrator logs the application and elevated migrations URLs on every
# full-mode boot. Those payloads keep the username (it is what tells the two
# credentials apart) and never print the password — including one that
# contains "/" or ":" and one carried in the query string.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only apps/web/auth/spec/unit/migrator_spec.rb

require_relative '../spec_helper'
require_relative '../../migrator'

RSpec.describe Auth::Migrator do
  describe '.redacted_url_for_log' do
    {
      'postgresql://app:s3cret@db:5432/auth' => 'postgresql://app:***@db:5432/auth',
      'postgresql://app:pa/ss@db/auth' => 'postgresql://app:***@db/auth',
      'postgresql://app:pa:ss@db/auth' => 'postgresql://app:***@db/auth',
      'postgresql://db/auth?password=s3cret' => 'postgresql://db/auth?***',
      'postgresql://app:s3cret@db/auth?sslmode=require' => 'postgresql://app:***@db/auth?***',
      'sqlite://data/auth.db' => 'sqlite://data/auth.db',
    }.each do |input, expected|
      it "renders #{input.inspect} as #{expected.inspect}" do
        expect(described_class.send(:redacted_url_for_log, input)).to eq(expected)
      end
    end

    it 'keeps an unset URL absent' do
      expect(described_class.send(:redacted_url_for_log, nil)).to be_nil
    end
  end

  describe '.log_migration_start' do
    it 'logs both URLs through the redactor' do
      logger = spy('sequel_logger')
      allow(described_class).to receive(:sequel_logger).and_return(logger)
      allow(Onetime).to receive(:auth_config)
        .and_return(instance_double(Onetime::AuthConfig, database_url: 'postgresql://app:pa/ss@db/auth?password=x'))

      described_class.send(:log_migration_start, true, 'postgresql://root:pa/ss@db/auth?password=x')

      expect(logger).to have_received(:info).with(
        'Auth migrations initializer running',
        database_url: 'postgresql://app:***@db/auth?***',
        migrations_url: 'postgresql://root:***@db/auth?***',
        using_elevated_credentials: true,
      )
    end
  end
end
