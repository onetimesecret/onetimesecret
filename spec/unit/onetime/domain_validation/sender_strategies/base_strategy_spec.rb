# spec/unit/onetime/domain_validation/sender_strategies/base_strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/domain_validation/sender_strategies/base_strategy'

RSpec.describe Onetime::DomainValidation::SenderStrategies::BaseStrategy do
  # Create a concrete subclass for testing since BaseStrategy has abstract methods
  let(:test_strategy_class) do
    Class.new(described_class) do
      # Make private methods public for testing
      public :lookup_txt_records, :lookup_cname_records, :lookup_mx_records
      public :dns_cache_key, :fetch_from_cache, :store_in_cache, :redis
      public :fetch_cache_bulk, :store_cache_bulk
      public :record_matches?, :txt_record_matches?, :spf_record_matches?
      public :with_retry

      def required_dns_records(_mailer_config)
        []
      end

      def verify_dns_records(_mailer_config)
        []
      end
    end
  end

  let(:strategy) { test_strategy_class.new }
  let(:hostname) { 'test.example.com' }
  let(:mock_redis) { instance_double('Redis') }

  before do
    allow(Onetime::CustomDomain).to receive(:dbclient).and_return(mock_redis)
  end

  describe 'DNS_CACHE_TTL' do
    it 'is 600 seconds (10 minutes)' do
      expect(described_class::DNS_CACHE_TTL).to eq(600)
    end
  end

  describe '#dns_cache_key' do
    it 'generates key in expected format' do
      key = strategy.dns_cache_key('Example.COM', 'TXT')
      expect(key).to eq('dns:cache:example.com:txt')
    end

    it 'downcases hostname and record type' do
      key = strategy.dns_cache_key('TEST.Example.COM', 'CNAME')
      expect(key).to eq('dns:cache:test.example.com:cname')
    end

    it 'strips trailing dots from hostname for consistent cache keys' do
      key_with_dot = strategy.dns_cache_key('example.com.', 'TXT')
      key_without_dot = strategy.dns_cache_key('example.com', 'TXT')
      expect(key_with_dot).to eq(key_without_dot)
      expect(key_with_dot).to eq('dns:cache:example.com:txt')
    end

    it 'normalizes FQDN with trailing dot to match non-FQDN' do
      # DNS servers often return FQDNs with trailing dots
      key_fqdn = strategy.dns_cache_key('selector._domainkey.example.com.', 'CNAME')
      key_plain = strategy.dns_cache_key('selector._domainkey.example.com', 'CNAME')
      expect(key_fqdn).to eq(key_plain)
    end

    it 'handles nil hostname gracefully' do
      key = strategy.dns_cache_key(nil, 'TXT')
      expect(key).to eq('dns:cache::txt')
    end
  end

  describe '#fetch_from_cache' do
    it 'returns nil when key does not exist' do
      allow(mock_redis).to receive(:get).with('dns:cache:test.example.com:txt').and_return(nil)

      result = strategy.fetch_from_cache(hostname, 'TXT')
      expect(result).to be_nil
    end

    it 'returns parsed array when cache hit' do
      cached_json = '["v=spf1 include:example.com ~all", "other-record"]'
      allow(mock_redis).to receive(:get).with('dns:cache:test.example.com:txt').and_return(cached_json)

      result = strategy.fetch_from_cache(hostname, 'TXT')
      expect(result).to eq(['v=spf1 include:example.com ~all', 'other-record'])
    end

    it 'returns empty array when cached (negative caching)' do
      allow(mock_redis).to receive(:get).with('dns:cache:test.example.com:txt').and_return('[]')

      result = strategy.fetch_from_cache(hostname, 'TXT')
      expect(result).to eq([])
    end

    it 'returns nil on JSON parse error' do
      allow(mock_redis).to receive(:get).with('dns:cache:test.example.com:txt').and_return('invalid json{')

      result = strategy.fetch_from_cache(hostname, 'TXT')
      expect(result).to be_nil
    end

    it 'returns nil on Redis connection error (graceful degradation)' do
      allow(mock_redis).to receive(:get).and_raise(Redis::ConnectionError, 'connection lost')

      # Cache failure should not break DNS lookups - returns nil to trigger live lookup
      result = strategy.fetch_from_cache(hostname, 'TXT')
      expect(result).to be_nil
    end
  end

  describe '#store_in_cache' do
    it 'stores values with default TTL' do
      expect(mock_redis).to receive(:setex)
        .with('dns:cache:test.example.com:txt', 600, '["record1","record2"]')

      strategy.store_in_cache(hostname, 'TXT', %w[record1 record2])
    end

    it 'stores empty array for negative caching' do
      expect(mock_redis).to receive(:setex)
        .with('dns:cache:test.example.com:cname', 600, '[]')

      strategy.store_in_cache(hostname, 'CNAME', [])
    end

    it 'accepts custom TTL' do
      expect(mock_redis).to receive(:setex)
        .with('dns:cache:test.example.com:mx', 300, '["mx.example.com"]')

      strategy.store_in_cache(hostname, 'MX', ['mx.example.com'], ttl: 300)
    end

    it 'silently handles Redis errors' do
      allow(mock_redis).to receive(:setex).and_raise(Redis::ConnectionError, 'connection lost')

      # Should not raise
      expect { strategy.store_in_cache(hostname, 'TXT', ['record']) }.not_to raise_error
    end
  end

  describe '#lookup_txt_records' do
    let(:mock_dns) { instance_double('Resolv::DNS') }
    let(:txt_resource) { double('TXT', strings: ['v=spf1 include:example.com ~all']) }

    before do
      allow(Resolv::DNS).to receive(:new).and_return(mock_dns)
      allow(mock_dns).to receive(:close)
    end

    context 'with cache hit' do
      before do
        allow(mock_redis).to receive(:get)
          .with('dns:cache:test.example.com:txt')
          .and_return('["cached-record"]')
      end

      it 'returns cached value without DNS lookup' do
        expect(mock_dns).not_to receive(:getresources)

        result = strategy.lookup_txt_records(hostname)
        expect(result).to eq(['cached-record'])
      end
    end

    context 'with cache miss' do
      before do
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_redis).to receive(:setex)
        allow(mock_dns).to receive(:getresources)
          .with(hostname, Resolv::DNS::Resource::IN::TXT)
          .and_return([txt_resource])
      end

      it 'performs DNS lookup' do
        expect(mock_dns).to receive(:getresources)
          .with(hostname, Resolv::DNS::Resource::IN::TXT)

        strategy.lookup_txt_records(hostname)
      end

      it 'caches the result' do
        expect(mock_redis).to receive(:setex)
          .with('dns:cache:test.example.com:txt', 600, '["v=spf1 include:example.com ~all"]')

        strategy.lookup_txt_records(hostname)
      end

      it 'returns DNS result' do
        result = strategy.lookup_txt_records(hostname)
        expect(result).to eq(['v=spf1 include:example.com ~all'])
      end
    end

    context 'with bypass_cache: true' do
      before do
        allow(mock_dns).to receive(:getresources)
          .with(hostname, Resolv::DNS::Resource::IN::TXT)
          .and_return([txt_resource])
      end

      it 'skips cache read' do
        expect(mock_redis).not_to receive(:get)

        strategy.lookup_txt_records(hostname, bypass_cache: true)
      end

      it 'skips cache write' do
        expect(mock_redis).not_to receive(:setex)

        strategy.lookup_txt_records(hostname, bypass_cache: true)
      end

      it 'performs live DNS lookup' do
        expect(mock_dns).to receive(:getresources)

        result = strategy.lookup_txt_records(hostname, bypass_cache: true)
        expect(result).to eq(['v=spf1 include:example.com ~all'])
      end
    end

    context 'with DNS error' do
      before do
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_dns).to receive(:getresources).and_raise(Resolv::ResolvError, 'NXDOMAIN')
      end

      it 'returns empty array' do
        result = strategy.lookup_txt_records(hostname)
        expect(result).to eq([])
      end
    end
  end

  describe '#lookup_cname_records' do
    let(:mock_dns) { instance_double('Resolv::DNS') }
    let(:cname_resource) { double('CNAME', name: double(to_s: 'target.example.com')) }

    before do
      allow(Resolv::DNS).to receive(:new).and_return(mock_dns)
      allow(mock_dns).to receive(:close)
    end

    context 'with cache hit' do
      before do
        allow(mock_redis).to receive(:get)
          .with('dns:cache:test.example.com:cname')
          .and_return('["cached-target.example.com"]')
      end

      it 'returns cached value without DNS lookup' do
        expect(mock_dns).not_to receive(:getresources)

        result = strategy.lookup_cname_records(hostname)
        expect(result).to eq(['cached-target.example.com'])
      end
    end

    context 'with cache miss' do
      before do
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_redis).to receive(:setex)
        allow(mock_dns).to receive(:getresources)
          .with(hostname, Resolv::DNS::Resource::IN::CNAME)
          .and_return([cname_resource])
      end

      it 'performs DNS lookup and caches result' do
        expect(mock_redis).to receive(:setex)
          .with('dns:cache:test.example.com:cname', 600, '["target.example.com"]')

        result = strategy.lookup_cname_records(hostname)
        expect(result).to eq(['target.example.com'])
      end
    end

    context 'with bypass_cache: true' do
      before do
        allow(mock_dns).to receive(:getresources)
          .with(hostname, Resolv::DNS::Resource::IN::CNAME)
          .and_return([cname_resource])
      end

      it 'skips cache entirely' do
        expect(mock_redis).not_to receive(:get)
        expect(mock_redis).not_to receive(:setex)

        result = strategy.lookup_cname_records(hostname, bypass_cache: true)
        expect(result).to eq(['target.example.com'])
      end
    end
  end

  describe '#lookup_mx_records' do
    let(:mock_dns) { instance_double('Resolv::DNS') }
    let(:mx_resource) { double('MX', exchange: double(to_s: 'mail.example.com')) }

    before do
      allow(Resolv::DNS).to receive(:new).and_return(mock_dns)
      allow(mock_dns).to receive(:close)
    end

    context 'with cache hit' do
      before do
        allow(mock_redis).to receive(:get)
          .with('dns:cache:test.example.com:mx')
          .and_return('["cached-mail.example.com"]')
      end

      it 'returns cached value without DNS lookup' do
        expect(mock_dns).not_to receive(:getresources)

        result = strategy.lookup_mx_records(hostname)
        expect(result).to eq(['cached-mail.example.com'])
      end
    end

    context 'with cache miss' do
      before do
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_redis).to receive(:setex)
        allow(mock_dns).to receive(:getresources)
          .with(hostname, Resolv::DNS::Resource::IN::MX)
          .and_return([mx_resource])
      end

      it 'performs DNS lookup and caches result' do
        expect(mock_redis).to receive(:setex)
          .with('dns:cache:test.example.com:mx', 600, '["mail.example.com"]')

        result = strategy.lookup_mx_records(hostname)
        expect(result).to eq(['mail.example.com'])
      end
    end

    context 'with bypass_cache: true' do
      before do
        allow(mock_dns).to receive(:getresources)
          .with(hostname, Resolv::DNS::Resource::IN::MX)
          .and_return([mx_resource])
      end

      it 'skips cache entirely' do
        expect(mock_redis).not_to receive(:get)
        expect(mock_redis).not_to receive(:setex)

        result = strategy.lookup_mx_records(hostname, bypass_cache: true)
        expect(result).to eq(['mail.example.com'])
      end
    end
  end

  describe 'negative caching' do
    let(:mock_dns) { instance_double('Resolv::DNS') }

    before do
      allow(Resolv::DNS).to receive(:new).and_return(mock_dns)
      allow(mock_dns).to receive(:close)
      allow(mock_redis).to receive(:get).and_return(nil)
    end

    it 'caches empty TXT results' do
      allow(mock_dns).to receive(:getresources).and_return([])
      expect(mock_redis).to receive(:setex)
        .with('dns:cache:test.example.com:txt', 600, '[]')

      strategy.lookup_txt_records(hostname)
    end

    it 'caches empty CNAME results' do
      allow(mock_dns).to receive(:getresources).and_return([])
      expect(mock_redis).to receive(:setex)
        .with('dns:cache:test.example.com:cname', 600, '[]')

      strategy.lookup_cname_records(hostname)
    end

    it 'caches empty MX results' do
      allow(mock_dns).to receive(:getresources).and_return([])
      expect(mock_redis).to receive(:setex)
        .with('dns:cache:test.example.com:mx', 600, '[]')

      strategy.lookup_mx_records(hostname)
    end
  end

  describe 'DNS retry constants' do
    it 'defines DNS_RETRY_MAX as 2' do
      expect(described_class::DNS_RETRY_MAX).to eq(2)
    end

    it 'defines DNS_RETRY_BASE_DELAY as 0.5 seconds' do
      expect(described_class::DNS_RETRY_BASE_DELAY).to eq(0.5)
    end

    it 'defines DNS_RETRIABLE predicate that accepts Resolv::ResolvTimeout' do
      predicate = described_class::DNS_RETRIABLE
      expect(predicate.call(Resolv::ResolvTimeout.new('timeout'))).to be true
    end

    it 'defines DNS_RETRIABLE predicate that rejects Resolv::ResolvError' do
      predicate = described_class::DNS_RETRIABLE
      expect(predicate.call(Resolv::ResolvError.new('NXDOMAIN'))).to be false
    end

    it 'defines DNS_RETRIABLE predicate that rejects other errors' do
      predicate = described_class::DNS_RETRIABLE
      expect(predicate.call(StandardError.new('other'))).to be false
    end
  end

  describe 'DNS retry behavior' do
    let(:mock_dns) { instance_double('Resolv::DNS') }
    let(:txt_resource) { double('TXT', strings: ['v=spf1 ~all']) }

    before do
      allow(Resolv::DNS).to receive(:new).and_return(mock_dns)
      allow(mock_dns).to receive(:close)
      allow(mock_redis).to receive(:get).and_return(nil)
      allow(mock_redis).to receive(:setex)
      # Stub sleep on the strategy instance to avoid test delays
      # (sleep resolves to Kernel#sleep on the instance, not the module)
      allow(strategy).to receive(:sleep)
    end

    describe '#lookup_txt_records' do
      it 'retries on Resolv::ResolvTimeout' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvTimeout, 'timeout' if call_count < 2

          [txt_resource]
        end

        result = strategy.lookup_txt_records(hostname)
        expect(result).to eq(['v=spf1 ~all'])
        expect(call_count).to eq(2)
      end

      it 'does not retry on Resolv::ResolvError' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvError, 'NXDOMAIN'
        end

        result = strategy.lookup_txt_records(hostname)
        expect(result).to eq([])
        expect(call_count).to eq(1)
      end

      it 'returns empty array after max retries on timeout' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvTimeout, 'timeout'
        end

        result = strategy.lookup_txt_records(hostname)
        expect(result).to eq([])
        # 1 initial + 2 retries = 3 total attempts
        expect(call_count).to eq(3)
      end

      it 'does not retry when cache hit' do
        allow(mock_redis).to receive(:get)
          .with('dns:cache:test.example.com:txt')
          .and_return('["cached"]')

        expect(mock_dns).not_to receive(:getresources)

        result = strategy.lookup_txt_records(hostname)
        expect(result).to eq(['cached'])
      end
    end

    describe '#lookup_cname_records' do
      let(:cname_resource) { double('CNAME', name: double(to_s: 'target.example.com')) }

      it 'retries on Resolv::ResolvTimeout' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvTimeout, 'timeout' if call_count < 2

          [cname_resource]
        end

        result = strategy.lookup_cname_records(hostname)
        expect(result).to eq(['target.example.com'])
        expect(call_count).to eq(2)
      end

      it 'does not retry on Resolv::ResolvError' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvError, 'NXDOMAIN'
        end

        result = strategy.lookup_cname_records(hostname)
        expect(result).to eq([])
        expect(call_count).to eq(1)
      end
    end

    describe '#lookup_mx_records' do
      let(:mx_resource) { double('MX', exchange: double(to_s: 'mail.example.com')) }

      it 'retries on Resolv::ResolvTimeout' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvTimeout, 'timeout' if call_count < 2

          [mx_resource]
        end

        result = strategy.lookup_mx_records(hostname)
        expect(result).to eq(['mail.example.com'])
        expect(call_count).to eq(2)
      end

      it 'does not retry on Resolv::ResolvError' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvError, 'NXDOMAIN'
        end

        result = strategy.lookup_mx_records(hostname)
        expect(result).to eq([])
        expect(call_count).to eq(1)
      end
    end
  end

  describe 'RetryHelper inclusion' do
    it 'includes RetryHelper module' do
      expect(described_class.included_modules).to include(Onetime::Utils::RetryHelper)
    end

    it 'provides with_retry instance method' do
      expect(strategy).to respond_to(:with_retry)
    end
  end

  describe '#fetch_cache_bulk' do
    let(:records) do
      [
        { host: 'spf.example.com', type: 'TXT' },
        { host: 'dkim.example.com', type: 'CNAME' },
        { host: 'mx.example.com', type: 'MX' },
      ]
    end

    it 'returns empty hash for empty records' do
      result = strategy.fetch_cache_bulk([])
      expect(result).to eq({})
    end

    it 'pipelines GET operations for all records' do
      expect(mock_redis).to receive(:pipelined).and_yield(mock_redis).and_return([nil, nil, nil])
      expect(mock_redis).to receive(:get).with('dns:cache:spf.example.com:txt')
      expect(mock_redis).to receive(:get).with('dns:cache:dkim.example.com:cname')
      expect(mock_redis).to receive(:get).with('dns:cache:mx.example.com:mx')

      strategy.fetch_cache_bulk(records)
    end

    it 'returns parsed values keyed by cache key' do
      cached_values = [
        '["v=spf1 ~all"]',
        '["target.example.com"]',
        nil,
      ]
      allow(mock_redis).to receive(:pipelined).and_yield(mock_redis).and_return(cached_values)
      allow(mock_redis).to receive(:get)

      result = strategy.fetch_cache_bulk(records)

      expect(result['dns:cache:spf.example.com:txt']).to eq(['v=spf1 ~all'])
      expect(result['dns:cache:dkim.example.com:cname']).to eq(['target.example.com'])
      expect(result).not_to have_key('dns:cache:mx.example.com:mx')
    end

    it 'handles JSON parse errors gracefully' do
      cached_values = ['invalid{json', '["valid"]']
      allow(mock_redis).to receive(:pipelined).and_yield(mock_redis).and_return(cached_values)
      allow(mock_redis).to receive(:get)

      result = strategy.fetch_cache_bulk(records.take(2))

      expect(result).not_to have_key('dns:cache:spf.example.com:txt')
      expect(result['dns:cache:dkim.example.com:cname']).to eq(['valid'])
    end

    it 'returns empty hash on Redis error' do
      allow(mock_redis).to receive(:pipelined).and_raise(Redis::ConnectionError, 'lost connection')

      result = strategy.fetch_cache_bulk(records)
      expect(result).to eq({})
    end
  end

  describe '#store_cache_bulk' do
    let(:results) do
      [
        { host: 'spf.example.com', type: 'TXT', actual: ['v=spf1 ~all'] },
        { host: 'dkim.example.com', type: 'CNAME', actual: ['target.example.com'] },
      ]
    end

    it 'does nothing for empty results' do
      expect(mock_redis).not_to receive(:pipelined)

      strategy.store_cache_bulk([])
    end

    it 'pipelines SETEX operations for all results' do
      expect(mock_redis).to receive(:pipelined).and_yield(mock_redis)
      expect(mock_redis).to receive(:setex)
        .with('dns:cache:spf.example.com:txt', 600, '["v=spf1 ~all"]')
      expect(mock_redis).to receive(:setex)
        .with('dns:cache:dkim.example.com:cname', 600, '["target.example.com"]')

      strategy.store_cache_bulk(results)
    end

    it 'accepts custom TTL' do
      expect(mock_redis).to receive(:pipelined).and_yield(mock_redis)
      expect(mock_redis).to receive(:setex)
        .with('dns:cache:spf.example.com:txt', 300, '["v=spf1 ~all"]')
      expect(mock_redis).to receive(:setex)
        .with('dns:cache:dkim.example.com:cname', 300, '["target.example.com"]')

      strategy.store_cache_bulk(results, ttl: 300)
    end

    it 'handles Redis errors gracefully' do
      allow(mock_redis).to receive(:pipelined).and_raise(Redis::ConnectionError, 'lost connection')

      expect { strategy.store_cache_bulk(results) }.not_to raise_error
    end
  end

  describe '#spf_record_matches?' do
    it 'matches SPF record with correct include directive' do
      expected = 'v=spf1 include:amazonses.com ~all'
      actual = ['v=spf1 include:amazonses.com include:sendgrid.net ~all']

      expect(strategy.spf_record_matches?(expected, actual)).to be true
    end

    it 'matches when include is present among multiple providers' do
      expected = 'v=spf1 include:sendgrid.net ~all'
      actual = ['v=spf1 include:amazonses.com include:sendgrid.net include:mailgun.org ~all']

      expect(strategy.spf_record_matches?(expected, actual)).to be true
    end

    it 'does not match when include directive is missing' do
      expected = 'v=spf1 include:amazonses.com ~all'
      actual = ['v=spf1 include:sendgrid.net ~all']

      expect(strategy.spf_record_matches?(expected, actual)).to be false
    end

    it 'does not match non-SPF records when looking for SPF' do
      expected = 'v=spf1 include:amazonses.com ~all'
      actual = ['some-other-txt-record include:amazonses.com']

      expect(strategy.spf_record_matches?(expected, actual)).to be false
    end

    it 'falls back to substring match when no include directive in expected' do
      expected = 'v=spf1 mx ~all'
      actual = ['v=spf1 mx ~all']

      expect(strategy.spf_record_matches?(expected, actual)).to be true
    end

    it 'is case insensitive for actual values' do
      # Note: spf_record_matches? receives normalized (downcased) expected
      # from record_matches?, so we test with lowercase expected
      expected = 'v=spf1 include:amazonses.com ~all'
      actual = ['V=SPF1 INCLUDE:AMAZONSES.COM ~ALL']

      expect(strategy.spf_record_matches?(expected, actual)).to be true
    end
  end

  describe '#txt_record_matches?' do
    it 'delegates to spf_record_matches? for SPF records' do
      expected = 'v=spf1 include:example.com ~all'
      actual = ['v=spf1 include:example.com ~all']

      expect(strategy).to receive(:spf_record_matches?).with(expected, actual).and_return(true)
      expect(strategy.txt_record_matches?(expected, actual)).to be true
    end

    it 'uses substring match for non-SPF TXT records' do
      expected = 'some-verification-token'
      actual = ['prefix-some-verification-token-suffix']

      expect(strategy.txt_record_matches?(expected, actual)).to be true
    end

    it 'is case insensitive for non-SPF records' do
      expected = 'verification-token'
      actual = ['VERIFICATION-TOKEN']

      expect(strategy.txt_record_matches?(expected, actual)).to be true
    end
  end

  describe '#record_matches?' do
    it 'delegates TXT records to txt_record_matches?' do
      expect(strategy).to receive(:txt_record_matches?).and_return(true)

      result = strategy.record_matches?('TXT', 'expected', ['actual'])
      expect(result).to be true
    end

    it 'matches CNAME records with exact match after normalization' do
      result = strategy.record_matches?('CNAME', 'target.example.com.', ['target.example.com'])
      expect(result).to be true
    end

    it 'matches MX records with exact match after normalization' do
      result = strategy.record_matches?('MX', 'mail.example.com', ['MAIL.EXAMPLE.COM.'])
      expect(result).to be true
    end

    it 'returns false for unknown record types' do
      result = strategy.record_matches?('AAAA', '::1', ['::1'])
      expect(result).to be false
    end
  end
end
