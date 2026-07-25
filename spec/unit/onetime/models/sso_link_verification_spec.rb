# spec/unit/onetime/models/sso_link_verification_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for Onetime::SsoLinkVerification — the single-use, mailbox-proof token
# behind the #3840 Phase 4 passwordless SSO linking flow.
#
# These exercise the real Familia-backed record on the test database (port 2121):
# persistence, the 15-minute TTL (criterion 3), string round-tripping of the
# snapshot fields, the display projection, and single-use consume semantics.
RSpec.describe Onetime::SsoLinkVerification do
  let(:issued) { [] }

  def issue(**overrides)
    record = described_class.issue(
      provider: overrides.fetch(:provider, 'google'),
      uid: overrides.fetch(:uid, 'sub-123'),
      email: overrides.fetch(:email, 'user@example.com'),
      account_id: overrides.fetch(:account_id, 42),
      sid: overrides.fetch(:sid, 'a' * 64),
      password_watermark: overrides.fetch(:password_watermark, 100),
      issuer: overrides.fetch(:issuer, 'https://accounts.google.com'),
    )
    issued << record
    record
  end

  after do
    issued.each { |r| r.delete! rescue nil }
  end

  describe 'TTL contract (criterion 3: <= 15 min)' do
    it 'sets DEFAULT_EXPIRATION to 900 seconds' do
      expect(described_class::DEFAULT_EXPIRATION).to eq(900)
    end

    it 'persists the record with a positive TTL no greater than 900s' do
      record = issue
      ttl    = Familia.dbclient.ttl(record.dbkey)
      expect(ttl).to be > 0
      expect(ttl).to be <= 900
    end
  end

  describe '.issue' do
    it 'mints a urlsafe token and persists a loadable record' do
      record = issue
      expect(record.token).to be_a(String)
      expect(record.token.length).to be >= 40

      loaded = described_class.load(record.token)
      expect(loaded).not_to be_nil
      expect(loaded.provider).to eq('google')
      expect(loaded.uid).to eq('sub-123')
      expect(loaded.email).to eq('user@example.com')
      expect(loaded.issuer).to eq('https://accounts.google.com')
    end

    it 'coerces the account id, watermark, and sid to strings (Familia string round-trip)' do
      loaded = described_class.load(issue(account_id: 42, password_watermark: 100, sid: 'b' * 64).token)
      expect(loaded.account_id).to eq('42')
      expect(loaded.password_watermark).to eq('100')
      expect(loaded.sid).to eq('b' * 64)
    end

    it 'stores a nil issuer as the empty-string sentinel (never nil)' do
      loaded = described_class.load(issue(issuer: nil).token)
      expect(loaded.issuer).to eq('')
    end

    it 'defaults an omitted watermark to "0"' do
      record = described_class.issue(
        provider: 'oidc', uid: 'u', email: 'x@y.com', account_id: 1,
      )
      issued << record
      expect(described_class.load(record.token).password_watermark).to eq('0')
    end
  end

  describe '#to_display' do
    it 'exposes ONLY the provider and claimed email (consent copy — criterion 2)' do
      expect(issue.to_display).to eq(provider: 'google', email: 'user@example.com')
    end

    it 'never leaks the account id, uid, issuer, sid, or watermark' do
      keys = issue.to_display.keys
      expect(keys).not_to include(:account_id, :uid, :issuer, :sid, :password_watermark)
    end
  end

  describe 'single-use consume (#delete!)' do
    it 'returns 1 on the first consume and removes the record' do
      record = issue
      expect(record.delete!).to eq(1)
      expect(described_class.load(record.token)).to be_nil
    end

    it 'returns 0 on a second consume of the same token (already spent)' do
      record = issue
      record.delete!
      expect(record.delete!).to eq(0)
    end
  end
end
