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

  describe 'X-Forwarded-Port beside a bare X-Forwarded-Host' do
    it 'supplies the port' do
      env = detect('Tenant.Example.COM', 'HTTP_X_FORWARDED_PORT' => '08443')

      expect(env[described_class.result_field_name]).to eq('tenant.example.com')
      expect(authority(env)).to eq('tenant.example.com:8443')
    end

    it 'does not replace a port written in X-Forwarded-Host' do
      env = detect('tenant.example.com:8443', 'HTTP_X_FORWARDED_PORT' => '9443')

      expect(authority(env)).to eq('tenant.example.com:8443')
    end

    it 'does not stand in for an unusable port written in X-Forwarded-Host' do
      env = detect('tenant.example.com:0', 'HTTP_X_FORWARDED_PORT' => '8443')

      expect(authority(env)).to be_nil
    end

    ['', ' ', '0', '65536', '-1', 'abc', '8443abc', '8443, 443', '8443,', '8443/path',
     "8443\r\nInjected: value"].each do |value|
      it "does not take a port from #{value.inspect}" do
        expect(authority(detect('tenant.example.com', 'HTTP_X_FORWARDED_PORT' => value))).to be_nil
      end
    end

    it 'is not read from a public peer' do
      env = detect('tenant.example.com', 'HTTP_X_FORWARDED_PORT' => '8443', 'REMOTE_ADDR' => '203.0.113.7')

      expect(authority(env)).to be_nil
    end

    it 'is not read when the peer failed configured proxy trust' do
      env = detect('tenant.example.com', 'HTTP_X_FORWARDED_PORT' => '8443',
        described_class::VIA_TRUSTED_PROXY_KEY => false)

      expect(authority(env)).to be_nil
    end

    it 'is not read when the host was detected on Host' do
      env = detect(nil, 'HTTP_X_FORWARDED_PORT' => '8443')

      expect(env[described_class.result_field_name]).to eq('origin.example.com')
      expect(authority(env)).to be_nil
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

  # `user:pw@host` is not host:port. Read that way it named the host "user".
  describe 'userinfo in an authority' do
    def detected(env)
      env[described_class.result_field_name]
    end

    def carriers(env)
      env[described_class.userinfo_carriers_field_name]
    end

    ['user:pw@tenant.example.com', 'user@tenant.example.com', 'tenant.example.com:pw@evil.test',
     'https://user:pw@tenant.example.com/', '@tenant.example.com', 'tenant.example.com@'].each do |value|
      it "detects no host for a trusted X-Forwarded-Host #{value.inspect}, and does not continue with Host" do
        env = detect(value)

        expect(detected(env)).to be_nil
        expect(authority(env)).to be_nil
      end

      it "detects no host for Host #{value.inspect}" do
        env = detect(nil, 'HTTP_HOST' => value)

        expect(detected(env)).to be_nil
      end

      it "does not read #{value.inspect} from a peer that is not a trusted proxy" do
        env = detect(value, 'REMOTE_ADDR' => '203.0.113.9')

        expect(detected(env)).to eq('origin.example.com')
        expect(carriers(env)).to be_nil
      end
    end

    it 'still continues with Host for the other unusable X-Forwarded-Host values' do
      ['10.0.0.7', 'localhost', '[::1]:8443', '-bad.example.com'].each do |value|
        expect(detected(detect(value))).to eq('origin.example.com')
      end
    end

    it 'keeps the outcome of a value with trailing text after the port' do
      expect(detected(detect('tenant.example.com:abc'))).to eq('tenant.example.com')
      expect(detected(detect('tenant.example.com:8443/path'))).to eq('tenant.example.com')
    end

    {
      'Apx-Incoming-Host' => { 'HTTP_APX_INCOMING_HOST' => 'user:pw@tenant.example.com' },
      'X-Original-Host' => { 'HTTP_X_ORIGINAL_HOST' => 'user@tenant.example.com' },
      'Forwarded' => { 'HTTP_FORWARDED' => 'for=192.0.2.1;host="user:pw@tenant.example.com"' },
    }.each do |name, headers|
      it "observes no host in #{name} and lists the header, for any peer" do
        ['127.0.0.1', '203.0.113.9'].each do |peer|
          env = detect(nil, 'REMOTE_ADDR' => peer, **headers)

          expect(detected(env)).to eq('origin.example.com')
          expect(carriers(env)).to eq([name])
          expect(env[described_class.unselected_hosts_field_name]).to be_nil
          expect(env[described_class.rfc7239_host_field_name]).to be_nil
        end
      end
    end

    it 'lists a multi-valued X-Forwarded-Host whose first value holds userinfo' do
      env = detect('user:pw@tenant.example.com, tenant.example.com')

      expect(detected(env)).to eq('origin.example.com')
      expect(carriers(env)).to eq(['X-Forwarded-Host'])
      expect(env[described_class.unselected_hosts_field_name]).to be_nil
    end

    it 'lists nothing when no observed carrier holds userinfo' do
      env = detect('tenant.example.com', 'HTTP_APX_INCOMING_HOST' => 'tenant.example.com',
        'HTTP_FORWARDED' => 'host=tenant.example.com')

      expect(env).not_to have_key(described_class.userinfo_carriers_field_name)
    end
  end
end
