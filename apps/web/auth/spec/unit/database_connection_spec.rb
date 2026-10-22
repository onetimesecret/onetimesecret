# apps/web/auth/spec/unit/database_connection_spec.rb
#
# frozen_string_literal: true

# An authdb URL that fails to parse must not put its password in the
# exception message. Two raises quote the URL: URI.parse inside
# Sequel.connect (a single-host URL with an unescaped "#", "@" or "%" in the
# password) and the multi-host parser's own format check. Both reach rake
# output and boot error logs.
#
# Also the timestamp readers (.utc_timestamp, .timestamp): the connection
# does not pin a database timezone, so a naive column comes back as the
# stored wall clock labelled with the host's zone, and the zone it was
# written in depends on the database and the writer (the module comment in
# database_connection.rb has the rules).
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only apps/web/auth/spec/unit/database_connection_spec.rb

require_relative '../spec_helper'
require_relative '../../database_connection'

RSpec.describe Auth::DatabaseConnection do
  describe 'reading timestamp columns' do
    let(:epoch) { 1_700_000_000 }
    # What Sequel returns for a UTC wall clock on a UTC-7 host with no
    # database timezone pinned: the components as stored, the host's offset.
    let(:utc_wall_clock_read_on_a_utc_minus_7_host) { Time.new(2023, 11, 14, 22, 13, 20, '-07:00') }

    describe '.utc_timestamp' do
      it 'reads the wall clock as UTC, whatever zone it is labelled with' do
        expect(described_class.utc_timestamp(utc_wall_clock_read_on_a_utc_minus_7_host)).to eq(Time.at(epoch).utc)
      end

      it 'is the identity on a value a pinned connection already returned in UTC' do
        expect(described_class.utc_timestamp(Time.at(epoch).utc)).to eq(Time.at(epoch).utc)
      end

      it 'keeps fractional seconds' do
        expect(described_class.utc_timestamp(Time.new(2023, 11, 14, 22, 13, 20.25r, '-07:00')).to_r).to eq(epoch + 0.25r)
      end

      it 'accepts a DateTime' do
        expect(described_class.utc_timestamp(DateTime.new(2023, 11, 14, 22, 13, 20, '-07:00')).to_i).to eq(epoch)
      end

      it 'is nil for nil' do
        expect(described_class.utc_timestamp(nil)).to be_nil
      end
    end

    describe '.timestamp' do
      it 'reads a PostgreSQL value as UTC' do
        db = double('postgres', database_type: :postgres)

        expect(described_class.timestamp(db, utc_wall_clock_read_on_a_utc_minus_7_host).to_i).to eq(epoch)
      end

      # Sequel wrote datetime(CURRENT_TIMESTAMP, 'localtime') and reads the
      # value back in the same zone, so its own Time is the instant.
      it 'reads a SQLite value as the local wall clock while current_timestamp_utc is unset' do
        db            = double('sqlite', database_type: :sqlite, current_timestamp_utc: false)
        local_instant = Time.new(2023, 11, 14, 15, 13, 20, '-07:00')

        expect(described_class.timestamp(db, local_instant).to_i).to eq(epoch)
      end

      it 'reads a SQLite value as UTC once current_timestamp_utc is set' do
        db = double('sqlite', database_type: :sqlite, current_timestamp_utc: true)

        expect(described_class.timestamp(db, utc_wall_clock_read_on_a_utc_minus_7_host).to_i).to eq(epoch)
      end

      it 'is nil for nil' do
        expect(described_class.timestamp(double('postgres', database_type: :postgres), nil)).to be_nil
      end
    end
  end

  describe '.redact_url' do
    {
      'postgresql://u:s3cret@db:5432/auth' => 'postgresql://***@db:5432/auth',
      'postgresql://u:s3cret@h1:5432,h2:5433/auth' => 'postgresql://***@h1:5432,h2:5433/auth',
      'postgresql://db/auth?password=s3cret' => 'postgresql://db/auth?***',
      'postgresql://u:s3cret@db/auth?sslmode=require' => 'postgresql://***@db/auth?***',
      'postgresql://u:p@ss:s3cret@db/auth' => 'postgresql://***@db/auth',
      'postgresql://db/auth?password=p@ss' => 'postgresql://***',
      'postgresql://u:pa?ss@db/auth' => 'postgresql://***',
      'sqlite://data/auth.db' => 'sqlite://data/auth.db',
      'sqlite://data/auth.db?password=s3cret' => 'sqlite://data/auth.db?***',
      # No userinfo in a SQLite URL: ":" and "@" are part of the path.
      'sqlite:///tmp/auth:archive@backup.db' => 'sqlite:///tmp/auth:archive@backup.db',
      'sqlite:///tmp/auth:archive@backup.db?password=s3cret' => 'sqlite:///tmp/auth:archive@backup.db?***',
    }.each do |input, expected|
      it "renders #{input.inspect} as #{expected.inspect}" do
        expect(described_class.redact_url(input)).to eq(expected)
      end
    end

    it 'does not raise on invalid UTF-8' do
      expect(described_class.redact_url("postgresql://u:s3\xFFcret@db/auth")).to eq('postgresql://***@db/auth')
    end
  end

  describe '.parse_postgres_multihost_url' do
    it 'leaves the password out of the format error' do
      expect { described_class.parse_postgres_multihost_url('postgresql://,u:s3cret@/auth,x') }
        .to raise_error(ArgumentError, 'Invalid PostgreSQL URL format: postgresql://***@/auth,x')
    end

    it 'leaves a query-string password out of the format error' do
      expect { described_class.parse_postgres_multihost_url('postgresql://,h2/auth?password=s3cret') }
        .to raise_error(ArgumentError, 'Invalid PostgreSQL URL format: postgresql://,h2/auth?***')
    end
  end

  describe '.open' do
    let(:url) { 'postgresql://u:p#s3cret@db/auth' }

    it 'leaves the password out of the URI parse error' do
      expect { described_class.open(url) }
        .to raise_error(URI::InvalidURIError, 'bad URI (is not URI?): postgresql://***@db/auth')
    end

    it 'drops the original error, whose message quotes the URL, as cause' do
      expect { described_class.open(url) }.to raise_error(having_attributes(cause: nil))
    end
  end
end
