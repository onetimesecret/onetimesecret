# spec/unit/onetime/cli/status_command_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'onetime/cli'
require 'onetime/cli/status_command'
require 'auth/database'

RSpec.describe Onetime::CLI::StatusCommand do
  subject(:command) { described_class.new }

  describe '#check_auth_database' do
    let(:tmpdir) { Dir.mktmpdir('ots-status-authdb') }
    let(:db_path) { File.join(tmpdir, 'auth.db') }
    let(:db_url) { "sqlite://#{db_path}" }
    let(:auth_config) { double('auth_config', full_enabled?: true, database_url: db_url) }

    before { allow(OT).to receive(:auth_config).and_return(auth_config) }

    after { FileUtils.remove_entry(tmpdir) }

    it 'is not required outside full mode, and connects to nothing', :aggregate_failures do
      allow(auth_config).to receive(:full_enabled?).and_return(false)
      allow(Auth::Database).to receive(:connect)

      expect(command.send(:check_auth_database)).to eq(status: 'not_required', enabled: false)
      expect(Auth::Database).not_to have_received(:connect)
    end

    it 'reports a reachable SQLite authdb', :aggregate_failures do
      result = command.send(:check_auth_database)

      expect(result).to include(status: 'connected', enabled: true, adapter: 'sqlite', url: db_url)
      expect(result[:version]).to match(/\A\d+\.\d+/)
    end

    # Auth::Database.connect is the one place the SQLite lock-wait settings
    # live; a bare Sequel.connect here would probe with different ones.
    it 'connects through Auth::Database.connect, with its SQLite settings', :aggregate_failures do
      probed = nil
      allow(Auth::Database).to receive(:connect).and_wrap_original do |original, *args, **opts|
        probed = original.call(*args, **opts)
      end

      command.send(:check_auth_database)

      expect(Auth::Database).to have_received(:connect).with(db_url).once
      expect(probed.transaction_mode).to eq(:immediate)
      expect(probed.opts[:timeout]).to eq(Auth::Database::SQLITE_BUSY_TIMEOUT_MS)
    end

    it 'is read-only: no migrations, no schema, and not the application connection', :aggregate_failures do
      allow(Auth::Migrator).to receive(:run_if_needed)
      allow(Auth::Database).to receive(:connection)

      command.send(:check_auth_database)

      expect(Auth::Migrator).not_to have_received(:run_if_needed)
      expect(Auth::Database).not_to have_received(:connection)

      db = Sequel.connect(db_url)
      begin
        expect(db.tables).to be_empty
      ensure
        db.disconnect
      end
    end

    it 'disconnects the probe connection' do
      probed = nil
      allow(Auth::Database).to receive(:connect).and_wrap_original do |original, *args, **opts|
        probed = original.call(*args, **opts)
      end

      command.send(:check_auth_database)

      expect(probed.pool.size).to eq(0)
    end

    it 'reports an unreachable authdb as an error, without raising' do
      allow(Auth::Database).to receive(:connect).and_raise(Sequel::DatabaseConnectionError, 'connection refused')

      expect(command.send(:check_auth_database)).to eq(status: 'error', enabled: true, error: 'connection refused')
    end
  end
end
