# frozen_string_literal: true

require 'spec_helper'
require 'middleware/detect_host'

RSpec.describe Rack::DetectHost do
  subject(:middleware) { described_class.new(->(_env) { [200, {}, ['ok']] }) }

  def detect(forwarded, **extra)
    env = {
      'HTTP_HOST' => 'origin.example.com:3000',
      'HTTP_X_FORWARDED_HOST' => forwarded,
      'REMOTE_ADDR' => '127.0.0.1',
      **extra,
    }
    middleware.call(env)
    env
  end

  def authority(env)
    env[described_class.forwarded_authority_field_name]
  end

  it 'retains a normalized authority without changing the detected hostname' do
    env = detect('Tenant.Example.COM:08443')

    expect(env[described_class.result_field_name]).to eq('tenant.example.com')
    expect(authority(env)).to eq('tenant.example.com:8443')
  end

  [1, 80, 443, 65535].each do |port|
    it "retains valid explicit port #{port}" do
      expect(authority(detect("tenant.example.com:#{port}"))).to eq("tenant.example.com:#{port}")
    end
  end

  [nil, 'tenant.example.com', 'tenant.example.com:0', 'tenant.example.com:65536',
   'tenant.example.com:-1', 'tenant.example.com:abc', 'tenant.example.com:8443/path',
   'https://tenant.example.com:8443', 'user@tenant.example.com:8443',
   'tenant.example.com:8443, tenant.example.com:8443',
   'tenant.example.com:8443,', "tenant.example.com:8443\r\nInjected: value",
   '127.0.0.1:8443', '[::1]:8443', 'bad_host.example.com:8443'].each do |value|
    it "does not retain an authority from #{value.inspect}" do
      expect(authority(detect(value))).to be_nil
    end
  end

  it 'does not trust a forwarded port from a public peer' do
    env = detect('tenant.example.com:8443', 'REMOTE_ADDR' => '203.0.113.7')

    expect(env[described_class.result_field_name]).to eq('origin.example.com')
    expect(authority(env)).to be_nil
  end

  [false, nil, 'true'].each do |trust|
    it "respects an explicit #{trust.inspect} proxy trust signal over the private-peer heuristic" do
      env = detect('tenant.example.com:8443', described_class::VIA_TRUSTED_PROXY_KEY => trust)

      expect(authority(env)).to be_nil
    end
  end

  it 'honors explicit proxy trust after the peer was rewritten to a public visitor IP' do
    env = detect('tenant.example.com:8443',
      'REMOTE_ADDR' => '203.0.113.7', described_class::VIA_TRUSTED_PROXY_KEY => true)

    expect(authority(env)).to eq('tenant.example.com:8443')
  end

  it 'never takes authority metadata from Host or observation-only carriers' do
    env = detect(nil,
      'HTTP_FORWARDED' => 'host=tenant.example.com:8443',
      'HTTP_X_ORIGINAL_HOST' => 'tenant.example.com:8443',
      'HTTP_APX_INCOMING_HOST' => 'tenant.example.com:8443')

    expect(env[described_class.result_field_name]).to eq('origin.example.com')
    expect(authority(env)).to be_nil
  end

  it 'clears authority metadata left by an earlier pass' do
    env = detect('tenant.example.com:8443')
    env.delete('HTTP_X_FORWARDED_HOST')
    middleware.call(env)

    expect(authority(env)).to be_nil
  end

  it 'keeps authority metadata alongside a renamed result field' do
    original = described_class.result_field_name
    begin
      described_class.result_field_name = 'test.detected_host'
      env = detect('tenant.example.com:8443')

      expect(env['test.detected_host']).to eq('tenant.example.com')
      expect(env['test.detected_host.forwarded_authority']).to eq('tenant.example.com:8443')
    ensure
      described_class.result_field_name = original
    end
  end
end
