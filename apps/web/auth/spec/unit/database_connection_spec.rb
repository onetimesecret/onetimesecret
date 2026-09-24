# apps/web/auth/spec/unit/database_connection_spec.rb
#
# frozen_string_literal: true

# An authdb URL that fails to parse must not put its password in the
# exception message. Two raises quote the URL: URI.parse inside
# Sequel.connect (a single-host URL with an unescaped "#", "@" or "%" in the
# password) and the multi-host parser's own format check. Both reach rake
# output and boot error logs.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only apps/web/auth/spec/unit/database_connection_spec.rb

require_relative '../spec_helper'
require_relative '../../database_connection'

RSpec.describe Auth::DatabaseConnection do
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
