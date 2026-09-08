# spec/unit/onetime/rodauth_admin_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::RodauthAdmin — the main repo's whole side of the
# integration with the standalone Rodauth Admin: an optional base URL and two
# outbound link builders. No request is ever made, so every path here is a
# pure function of config + auth mode.

require 'spec_helper'
require 'onetime/rodauth_admin'

RSpec.describe Onetime::RodauthAdmin do
  def stub_config(url)
    allow(OT).to receive(:conf).and_return({ 'site' => { 'admin' => { 'rodauth_admin_url' => url } } })
  end

  def stub_mode(full:)
    allow(Onetime.auth_config).to receive(:full_enabled?).and_return(full)
  end

  describe '.base_url' do
    it 'is nil when the key is absent' do
      allow(OT).to receive(:conf).and_return({ 'site' => {} })
      expect(described_class.base_url).to be_nil
    end

    it 'treats a blank value as unset (ENV renders empty strings)' do
      stub_config('   ')
      expect(described_class.base_url).to be_nil
    end

    it 'strips trailing slashes so links never double them' do
      stub_config('http://127.0.0.1:9292///')
      expect(described_class.base_url).to eq('http://127.0.0.1:9292')
    end

    it 'accepts https' do
      stub_config('https://admin.example.com')
      expect(described_class.base_url).to eq('https://admin.example.com')
    end

    context 'with a value that is not an absolute http(s) URL' do
      before do
        # The warn-once memo persists on the module across examples.
        described_class.instance_variable_set(:@warned_invalid_url, nil)
        allow(OT).to receive(:le)
      end

      it 'treats a schemeless host:port value as unset (dead-link trap)' do
        stub_config('admin.example.com:9292')
        expect(described_class.base_url).to be_nil
      end

      it 'rejects a non-http scheme' do
        stub_config('ftp://admin.example.com')
        expect(described_class.base_url).to be_nil
      end

      it 'rejects an unparseable value' do
        stub_config('http://[bad')
        expect(described_class.base_url).to be_nil
      end

      it 'warns once, naming the misconfiguration' do
        stub_config('admin.example.com:9292')
        expect(OT).to receive(:le).once.with(/RODAUTH_ADMIN_URL is not an absolute/)
        described_class.base_url
        described_class.base_url
      end
    end
  end

  describe '.console_url' do
    it 'is nil in simple auth mode even when configured (nothing to link to)' do
      stub_config('http://127.0.0.1:9292')
      stub_mode(full: false)
      expect(described_class.console_url).to be_nil
    end

    it 'is nil in full mode when unset' do
      stub_config(nil)
      stub_mode(full: true)
      expect(described_class.console_url).to be_nil
    end

    it 'is the base URL in full mode when configured' do
      stub_config('http://127.0.0.1:9292/')
      stub_mode(full: true)
      expect(described_class.console_url).to eq('http://127.0.0.1:9292')
    end
  end

  describe '.account_url' do
    before do
      stub_config('http://127.0.0.1:9292')
      stub_mode(full: true)
    end

    it "targets the admin's inbound lookup route keyed by external_id" do
      expect(described_class.account_url('ur_abc')).to eq('http://127.0.0.1:9292/account?q=ur_abc')
    end

    it 'url-encodes the extid so data cannot rewrite the link target' do
      expect(described_class.account_url('ur/../x?y#z'))
        .to eq('http://127.0.0.1:9292/account?q=ur%2F..%2Fx%3Fy%23z')
    end

    it 'is nil for a nil extid' do
      expect(described_class.account_url(nil)).to be_nil
    end

    it 'is nil for a whitespace-only extid' do
      expect(described_class.account_url('  ')).to be_nil
    end

    it 'is nil outside full mode' do
      stub_mode(full: false)
      expect(described_class.account_url('ur_abc')).to be_nil
    end
  end
end
