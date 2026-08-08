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
      public :lookup_txt_records, :lookup_cname_records, :lookup_mx_records, :classify_dns_error
      public :dns_cache_key, :fetch_from_cache, :store_in_cache, :redis
      public :fetch_cache_bulk, :store_cache_bulk
      public :record_matches?, :txt_record_matches?, :spf_record_matches?
      public :verify_record_with_cache, :evaluate_record_set, :select_txt_record_set
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

        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq(['cached-record'])
        expect(error_type).to be_nil
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

      it 'returns DNS result as tuple' do
        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq(['v=spf1 include:example.com ~all'])
        expect(error_type).to be_nil
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

        values, error_type = strategy.lookup_txt_records(hostname, bypass_cache: true)
        expect(values).to eq(['v=spf1 include:example.com ~all'])
        expect(error_type).to be_nil
      end
    end

    context 'with DNS error' do
      before do
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_dns).to receive(:getresources).and_raise(Resolv::ResolvError, 'NXDOMAIN')
      end

      it 'returns empty array with not_found error_type' do
        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq([])
        expect(error_type).to eq('not_found')
      end
    end

    context 'with DNS timeout' do
      before do
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_dns).to receive(:getresources).and_raise(Resolv::ResolvTimeout, 'timeout')
        allow(strategy).to receive(:sleep) # Skip retry delays
      end

      it 'returns empty array with timeout error_type' do
        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq([])
        expect(error_type).to eq('timeout')
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

        values, error_type = strategy.lookup_cname_records(hostname)
        expect(values).to eq(['cached-target.example.com'])
        expect(error_type).to be_nil
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

        values, error_type = strategy.lookup_cname_records(hostname)
        expect(values).to eq(['target.example.com'])
        expect(error_type).to be_nil
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

        values, error_type = strategy.lookup_cname_records(hostname, bypass_cache: true)
        expect(values).to eq(['target.example.com'])
        expect(error_type).to be_nil
      end
    end

    context 'with DNS error' do
      before do
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_dns).to receive(:getresources).and_raise(Resolv::ResolvError, 'NXDOMAIN')
      end

      it 'returns empty array with not_found error_type' do
        values, error_type = strategy.lookup_cname_records(hostname)
        expect(values).to eq([])
        expect(error_type).to eq('not_found')
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

        values, error_type = strategy.lookup_mx_records(hostname)
        expect(values).to eq(['cached-mail.example.com'])
        expect(error_type).to be_nil
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

        values, error_type = strategy.lookup_mx_records(hostname)
        expect(values).to eq(['mail.example.com'])
        expect(error_type).to be_nil
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

        values, error_type = strategy.lookup_mx_records(hostname, bypass_cache: true)
        expect(values).to eq(['mail.example.com'])
        expect(error_type).to be_nil
      end
    end

    context 'with DNS error' do
      before do
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_dns).to receive(:getresources).and_raise(Resolv::ResolvError, 'NXDOMAIN')
      end

      it 'returns empty array with not_found error_type' do
        values, error_type = strategy.lookup_mx_records(hostname)
        expect(values).to eq([])
        expect(error_type).to eq('not_found')
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

        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq(['v=spf1 ~all'])
        expect(error_type).to be_nil
        expect(call_count).to eq(2)
      end

      it 'does not retry on Resolv::ResolvError' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvError, 'NXDOMAIN'
        end

        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq([])
        expect(error_type).to eq('not_found')
        expect(call_count).to eq(1)
      end

      it 'returns empty array with timeout error_type after max retries' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvTimeout, 'timeout'
        end

        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq([])
        expect(error_type).to eq('timeout')
        # 1 initial + 2 retries = 3 total attempts
        expect(call_count).to eq(3)
      end

      it 'does not retry when cache hit' do
        allow(mock_redis).to receive(:get)
          .with('dns:cache:test.example.com:txt')
          .and_return('["cached"]')

        expect(mock_dns).not_to receive(:getresources)

        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq(['cached'])
        expect(error_type).to be_nil
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

        values, error_type = strategy.lookup_cname_records(hostname)
        expect(values).to eq(['target.example.com'])
        expect(error_type).to be_nil
        expect(call_count).to eq(2)
      end

      it 'does not retry on Resolv::ResolvError' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvError, 'NXDOMAIN'
        end

        values, error_type = strategy.lookup_cname_records(hostname)
        expect(values).to eq([])
        expect(error_type).to eq('not_found')
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

        values, error_type = strategy.lookup_mx_records(hostname)
        expect(values).to eq(['mail.example.com'])
        expect(error_type).to be_nil
        expect(call_count).to eq(2)
      end

      it 'does not retry on Resolv::ResolvError' do
        call_count = 0
        allow(mock_dns).to receive(:getresources) do
          call_count += 1
          raise Resolv::ResolvError, 'NXDOMAIN'
        end

        values, error_type = strategy.lookup_mx_records(hostname)
        expect(values).to eq([])
        expect(error_type).to eq('not_found')
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

    # Issue #4023: opaque provider verification tokens require exact match.
    # The old substring behavior allowed 'prefix-token-suffix' to satisfy
    # 'token' — deliberately tightened.
    it 'requires exact match for opaque tokens, not substring (issue #4023)' do
      expected = 'some-verification-token'

      expect(strategy.txt_record_matches?(expected, ['some-verification-token'])).to be true
      expect(strategy.txt_record_matches?(expected, ['prefix-some-verification-token-suffix'])).to be false
    end

    it 'is case sensitive for opaque tokens (issue #4023)' do
      expected = 'verification-token'

      expect(strategy.txt_record_matches?(expected, ['verification-token'])).to be true
      expect(strategy.txt_record_matches?(expected, ['VERIFICATION-TOKEN'])).to be false
    end

    it 'trims edge whitespace on the actual value for opaque tokens' do
      expect(strategy.txt_record_matches?('token-abc', ['  token-abc  '])).to be true
    end

    context 'with DMARC tag-list records (issue #4023)' do
      it 'matches semantically equivalent formatting variants' do
        # Real Lettermint case (eu-direct.metalbaum.dev): published record has
        # spaces after ";" and a trailing ";" — same tag list per RFC 6376 3.2.
        expect(strategy.txt_record_matches?('v=DMARC1;p=none', ['v=DMARC1; p=none;'])).to be true
      end

      it 'is satisfied by a published record with extra customer tags' do
        expect(
          strategy.txt_record_matches?('v=DMARC1;p=none', ['v=DMARC1; p=none; rua=mailto:dmarc@example.com']),
        ).to be true
      end

      it 'treats a hardened published policy (p=reject) as satisfying p=none' do
        expect(strategy.txt_record_matches?('v=DMARC1; p=none;', ['v=DMARC1; p=reject'])).to be true
      end

      it 'compares policy keywords case-insensitively (RFC 5234 ABNF keywords)' do
        expect(strategy.txt_record_matches?('v=DMARC1;p=none', ['v=DMARC1; p=NONE'])).to be true
      end

      it 'rejects a weaker published policy (p=none against expected p=quarantine)' do
        expect(strategy.txt_record_matches?('v=DMARC1;p=quarantine', ['v=DMARC1; p=none'])).to be false
      end

      it 'rejects a published policy outside the RFC 7489 keywords (p=bogus)' do
        expect(strategy.txt_record_matches?('v=DMARC1;p=none', ['v=DMARC1; p=bogus'])).to be false
      end

      it 'rejects an empty published policy value (p=)' do
        expect(strategy.txt_record_matches?('v=DMARC1;p=none', ['v=DMARC1; p='])).to be false
      end

      it 'applies the same strength ordering to sp=' do
        expect(strategy.txt_record_matches?('v=DMARC1;p=none;sp=none', ['v=DMARC1;p=none;sp=reject'])).to be true
        expect(strategy.txt_record_matches?('v=DMARC1;p=none;sp=reject', ['v=DMARC1;p=none;sp=none'])).to be false
      end

      it 'does not match when an expected tag is absent' do
        expect(strategy.txt_record_matches?('v=DMARC1;p=none', ['v=DMARC1'])).to be false
      end

      it 'never matches a published record invalidated by duplicate tags' do
        expect(strategy.txt_record_matches?('v=DMARC1;p=none', ['v=DMARC1;p=none;p=reject'])).to be false
      end
    end

    context 'with DKIM tag-list records (issue #4023)' do
      it 'matches by tag subset with case-insensitive k= and wrapped p=' do
        expected = 'v=DKIM1;k=rsa;p=MIGfMA0GCSqGSIb3'
        actual = ['v=DKIM1; k=RSA; p=MIGfMA0G CSqG SIb3'] # DNS UI wraps long keys

        expect(strategy.txt_record_matches?(expected, actual)).to be true
      end

      it 'compares p= base64 key data case-sensitively (RFC 6376 3.2)' do
        expected = 'v=DKIM1;k=rsa;p=MIGfMA0GCSqGSIb3'
        actual = ['v=DKIM1; k=rsa; p=migfma0gcsqgsib3']

        expect(strategy.txt_record_matches?(expected, actual)).to be false
      end
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

    it 'does not downcase TXT expected values before dispatch (issue #4023)' do
      # Global downcasing would case-fold DKIM base64 p= key data; the
      # published key must match the expected key byte-for-byte.
      expect(strategy.record_matches?('TXT', 'v=DKIM1;p=MIGfMA0', ['v=DKIM1; p=MIGfMA0'])).to be true
      expect(strategy.record_matches?('TXT', 'v=DKIM1;p=MIGfMA0', ['v=DKIM1; p=migfma0'])).to be false
    end
  end

  describe '#select_txt_record_set' do
    it 'passes non-TXT sets through unfiltered' do
      candidates, ambiguous = strategy.select_txt_record_set(
        'CNAME', 'target.example.com', ['target.example.com.', 'other.example.com.'],
      )
      expect(candidates).to eq(['target.example.com.', 'other.example.com.'])
      expect(ambiguous).to be false
    end

    it 'filters DMARC candidates by discriminator, discarding unrelated TXT records' do
      candidates, ambiguous = strategy.select_txt_record_set(
        'TXT', 'v=DMARC1;p=none', ['google-site-verification=abc', 'v=DMARC1; p=none;', 'MS=ms123'],
      )
      expect(candidates).to eq(['v=DMARC1; p=none;'])
      expect(ambiguous).to be false
    end

    it 'flags two surviving DMARC records as ambiguous' do
      _, ambiguous = strategy.select_txt_record_set(
        'TXT', 'v=DMARC1;p=none', ['v=DMARC1; p=none;', 'v=DMARC1; p=reject'],
      )
      expect(ambiguous).to be true
    end

    it 'flags two surviving SPF records as ambiguous (RFC 7208 permerror)' do
      _, ambiguous = strategy.select_txt_record_set(
        'TXT', 'v=spf1 include:amazonses.com ~all', ['v=spf1 include:amazonses.com ~all', 'v=spf1 -all'],
      )
      expect(ambiguous).to be true
    end

    it 'does not apply uniqueness selection to DKIM expectations' do
      # Spec scope: record-set selection applies to DMARC and SPF only.
      candidates, ambiguous = strategy.select_txt_record_set(
        'TXT', 'v=DKIM1;k=rsa;p=ABC', ['v=DKIM1;k=rsa;p=ABC', 'v=DKIM1;k=rsa;p=DEF'],
      )
      expect(candidates).to eq(['v=DKIM1;k=rsa;p=ABC', 'v=DKIM1;k=rsa;p=DEF'])
      expect(ambiguous).to be false
    end

    it 'does not apply uniqueness selection to opaque token expectations' do
      candidates, ambiguous = strategy.select_txt_record_set(
        'TXT', 'token-abc', ['token-abc', 'token-def'],
      )
      expect(candidates).to eq(%w[token-abc token-def])
      expect(ambiguous).to be false
    end
  end

  describe '#verify_record_with_cache' do
    let(:resolver) { instance_double('Resolv::DNS') }
    let(:dmarc_record) do
      {
        type: 'TXT',
        host: '_dmarc.example.com',
        value: 'v=DMARC1;p=none',
        purpose: 'DMARC',
      }
    end

    def txt_resources(values)
      values.map { |v| double('TXT', strings: [v]) }
    end

    context 'cache-hit branch' do
      it 'fails with ambiguous_record_set when the cached set has two DMARC records' do
        result = strategy.verify_record_with_cache(
          dmarc_record,
          resolver: resolver,
          cached_value: ['v=DMARC1; p=none;', 'v=DMARC1; p=reject'],
          bypass_cache: false,
        )

        expect(result[:verified]).to be false
        expect(result[:error_type]).to eq('ambiguous_record_set')
        expect(result[:from_cache]).to be true
      end

      it 'fails duplicate IDENTICAL cached DMARC records too (never a pass)' do
        result = strategy.verify_record_with_cache(
          dmarc_record,
          resolver: resolver,
          cached_value: ['v=DMARC1;p=none', 'v=DMARC1;p=none'],
          bypass_cache: false,
        )

        expect(result[:verified]).to be false
        expect(result[:error_type]).to eq('ambiguous_record_set')
      end

      it 'verifies one cached DMARC record among unrelated junk TXT records' do
        cached = ['google-site-verification=abc', 'v=DMARC1; p=none;', 'MS=ms123']
        result = strategy.verify_record_with_cache(
          dmarc_record,
          resolver: resolver,
          cached_value: cached,
          bypass_cache: false,
        )

        expect(result[:verified]).to be true
        expect(result).not_to have_key(:error_type)
        # :actual keeps the full unfiltered set for diagnostics and re-caching
        expect(result[:actual]).to eq(cached)
      end

      it 'keeps not-found semantics when zero DMARC records survive' do
        result = strategy.verify_record_with_cache(
          dmarc_record,
          resolver: resolver,
          cached_value: ['google-site-verification=abc'],
          bypass_cache: false,
        )

        expect(result[:verified]).to be false
        expect(result).not_to have_key(:error_type)
        expect(result[:from_cache]).to be true
      end
    end

    context 'live branch' do
      it 'fails with ambiguous_record_set when DNS returns two DMARC records' do
        allow(resolver).to receive(:getresources)
          .with('_dmarc.example.com', Resolv::DNS::Resource::IN::TXT)
          .and_return(txt_resources(['v=DMARC1; p=none;', 'v=DMARC1; p=reject']))

        result = strategy.verify_record_with_cache(
          dmarc_record,
          resolver: resolver,
          cached_value: nil,
          bypass_cache: false,
        )

        expect(result[:verified]).to be false
        expect(result[:error_type]).to eq('ambiguous_record_set')
        expect(result[:from_cache]).to be false
      end

      it 'fails with ambiguous_record_set when DNS returns two SPF records' do
        spf_record = {
          type: 'TXT',
          host: 'example.com',
          value: 'v=spf1 include:amazonses.com ~all',
          purpose: 'SPF',
        }
        allow(resolver).to receive(:getresources)
          .with('example.com', Resolv::DNS::Resource::IN::TXT)
          .and_return(txt_resources(['v=spf1 include:amazonses.com ~all', 'v=spf1 -all']))

        result = strategy.verify_record_with_cache(
          spf_record,
          resolver: resolver,
          cached_value: nil,
          bypass_cache: false,
        )

        expect(result[:verified]).to be false
        expect(result[:error_type]).to eq('ambiguous_record_set')
      end

      it 'verifies one live DMARC record among unrelated junk TXT records' do
        live = ['MS=ms123', 'v=DMARC1; p=none;', 'google-site-verification=abc']
        allow(resolver).to receive(:getresources)
          .with('_dmarc.example.com', Resolv::DNS::Resource::IN::TXT)
          .and_return(txt_resources(live))

        result = strategy.verify_record_with_cache(
          dmarc_record,
          resolver: resolver,
          cached_value: nil,
          bypass_cache: false,
        )

        expect(result[:verified]).to be true
        expect(result).not_to have_key(:error_type)
        expect(result[:actual]).to eq(live)
      end

      it 'reports the DNS lookup error_type when the lookup itself fails' do
        allow(resolver).to receive(:getresources)
          .and_raise(Resolv::ResolvError, 'NXDOMAIN')

        result = strategy.verify_record_with_cache(
          dmarc_record,
          resolver: resolver,
          cached_value: nil,
          bypass_cache: false,
        )

        expect(result[:verified]).to be false
        expect(result[:error_type]).to eq('not_found')
        expect(result[:actual]).to eq([])
      end

      it 'ignores the cached value when bypass_cache is true' do
        # Stale two-record cache must not produce a false ambiguity once DNS
        # has been fixed to a single record.
        allow(resolver).to receive(:getresources)
          .with('_dmarc.example.com', Resolv::DNS::Resource::IN::TXT)
          .and_return(txt_resources(['v=DMARC1; p=none;']))

        result = strategy.verify_record_with_cache(
          dmarc_record,
          resolver: resolver,
          cached_value: ['v=DMARC1;p=none', 'v=DMARC1;p=reject'],
          bypass_cache: true,
        )

        expect(result[:verified]).to be true
        expect(result).not_to have_key(:error_type)
        expect(result[:from_cache]).to be false
      end
    end
  end

  describe '#classify_dns_error' do
    it 'returns timeout for Resolv::ResolvTimeout' do
      error = Resolv::ResolvTimeout.new('DNS timeout')
      expect(strategy.classify_dns_error(error)).to eq('timeout')
    end

    it 'returns not_found for Resolv::ResolvError' do
      error = Resolv::ResolvError.new('NXDOMAIN')
      expect(strategy.classify_dns_error(error)).to eq('not_found')
    end

    it 'returns network_error for SocketError' do
      error = SocketError.new('connection refused')
      expect(strategy.classify_dns_error(error)).to eq('network_error')
    end

    it 'returns network_error for other StandardError' do
      error = StandardError.new('unknown error')
      expect(strategy.classify_dns_error(error)).to eq('network_error')
    end

    it 'returns network_error for IOError' do
      error = IOError.new('stream closed')
      expect(strategy.classify_dns_error(error)).to eq('network_error')
    end
  end

  describe 'error_type in verification results' do
    let(:mock_dns) { instance_double('Resolv::DNS') }

    before do
      allow(Resolv::DNS).to receive(:new).and_return(mock_dns)
      allow(mock_dns).to receive(:close)
      allow(mock_redis).to receive(:get).and_return(nil)
    end

    context 'when DNS lookup fails with ResolvError' do
      before do
        allow(mock_dns).to receive(:getresources).and_raise(Resolv::ResolvError, 'NXDOMAIN')
      end

      it 'includes error_type in lookup result' do
        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq([])
        expect(error_type).to eq('not_found')
      end
    end

    context 'when DNS lookup fails with ResolvTimeout' do
      before do
        allow(mock_dns).to receive(:getresources).and_raise(Resolv::ResolvTimeout, 'timeout')
        allow(strategy).to receive(:sleep)
      end

      it 'includes error_type in lookup result' do
        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq([])
        expect(error_type).to eq('timeout')
      end
    end

    context 'when DNS lookup succeeds' do
      let(:txt_resource) { double('TXT', strings: ['v=spf1 ~all']) }

      before do
        allow(mock_dns).to receive(:getresources).and_return([txt_resource])
        allow(mock_redis).to receive(:setex)
      end

      it 'returns nil error_type' do
        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq(['v=spf1 ~all'])
        expect(error_type).to be_nil
      end
    end

    context 'when value is from cache' do
      before do
        allow(mock_redis).to receive(:get)
          .with('dns:cache:test.example.com:txt')
          .and_return('["cached-value"]')
      end

      it 'returns nil error_type for cache hits' do
        values, error_type = strategy.lookup_txt_records(hostname)
        expect(values).to eq(['cached-value'])
        expect(error_type).to be_nil
      end
    end
  end

  describe '#resolve_domain' do
    let(:resolve_strategy_class) do
      Class.new(described_class) do
        public :resolve_domain

        def required_dns_records(_mailer_config)
          []
        end

        def verify_dns_records(_mailer_config)
          []
        end
      end
    end

    let(:resolve_strategy) { resolve_strategy_class.new }

    it 'extracts domain from from_address' do
      config = double('mailer_config', from_address: 'user@example.com', domain_id: 'cd:1')
      expect(resolve_strategy.resolve_domain(config)).to eq('example.com')
    end

    it 'extracts sender domain distinct from display_domain' do
      config = double('mailer_config', from_address: 'roger@metalbaum.dev', domain_id: 'cd:2')
      expect(resolve_strategy.resolve_domain(config)).to eq('metalbaum.dev')
    end

    it 'handles subdomain in from_address' do
      config = double('mailer_config', from_address: 'noreply@mail.example.com', domain_id: 'cd:3')
      expect(resolve_strategy.resolve_domain(config)).to eq('mail.example.com')
    end

    it 'raises ArgumentError when from_address is nil' do
      config = double('mailer_config', from_address: nil, domain_id: 'cd:4')
      expect { resolve_strategy.resolve_domain(config) }
        .to raise_error(ArgumentError, /has no valid from_address/)
    end

    it 'raises ArgumentError when from_address is empty' do
      config = double('mailer_config', from_address: '', domain_id: 'cd:5')
      expect { resolve_strategy.resolve_domain(config) }
        .to raise_error(ArgumentError, /has no valid from_address/)
    end

    it 'raises ArgumentError when from_address has no @ sign' do
      config = double('mailer_config', from_address: 'no-at-sign', domain_id: 'cd:6')
      expect { resolve_strategy.resolve_domain(config) }
        .to raise_error(ArgumentError, /has no valid from_address/)
    end

    it 'raises ArgumentError when from_address is bare @' do
      config = double('mailer_config', from_address: '@', domain_id: 'cd:7')
      expect { resolve_strategy.resolve_domain(config) }
        .to raise_error(ArgumentError, /has empty domain in from_address/)
    end

    it 'handles multi-level TLD correctly' do
      config = double('mailer_config', from_address: 'info@company.co.uk', domain_id: 'cd:8')
      expect(resolve_strategy.resolve_domain(config)).to eq('company.co.uk')
    end

    it 'mirrors real-world dev.metalbaum.dev vs metalbaum.dev scenario' do
      # display_domain is dev.metalbaum.dev but sender is roger@metalbaum.dev
      config = double('mailer_config', from_address: 'roger@metalbaum.dev', domain_id: 'cd:9')
      domain = resolve_strategy.resolve_domain(config)
      expect(domain).to eq('metalbaum.dev')
      expect(domain).not_to eq('dev.metalbaum.dev')
    end
  end
end
