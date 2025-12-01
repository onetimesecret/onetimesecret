# tests/unit/ruby/rspec/apps/api/v2/models/rate_limit_spec.rb
#
# Tests for V2::RateLimit model covering:
# - [#2111] DEFAULT_LIMIT constant value (100)
# - [#2111] event_limit string key lookup fix

require_relative '../../../../spec_helper'
require 'v2/models/rate_limit'

RSpec.describe V2::RateLimit do
  # Reset registered events before each test to ensure isolation
  before(:each) do
    # Clear any previously registered events
    V2::RateLimit.instance_variable_set(:@events, {})
  end

  describe 'DEFAULT_LIMIT' do
    # [#2111] Increase default rate limit
    # Helps minimize the impact of rate limiting events in the case of a bug
    # or missing configuration.
    it 'is set to 100' do
      expect(V2::RateLimit::DEFAULT_LIMIT).to eq(100)
    end

    it 'is used when event is not explicitly configured' do
      expect(V2::RateLimit.event_limit(:unconfigured_event)).to eq(100)
    end

    it 'is used when event is not explicitly configured (string key)' do
      expect(V2::RateLimit.event_limit('unconfigured_event')).to eq(100)
    end
  end

  describe '.event_limit' do
    # [#2111] Fix event limit lookup
    # When register_events is called at start time, it is passed the
    # rate_limit settings as-is. With the config change from symbol keys to
    # strings, the matching of rate limit event to the hash of pre-configured
    # events didn't match. Now events are treated as strings so they match
    # the config setting correctly.

    context 'when events are registered with string keys' do
      before(:each) do
        # Simulate config loading which passes string keys
        V2::RateLimit.register_events({
          'create_secret' => 50,
          'view_secret' => 200,
          'api_call' => 1000
        })
      end

      it 'finds limit when queried with symbol key' do
        expect(V2::RateLimit.event_limit(:create_secret)).to eq(50)
      end

      it 'finds limit when queried with string key' do
        expect(V2::RateLimit.event_limit('create_secret')).to eq(50)
      end

      it 'returns correct limit for each configured event' do
        expect(V2::RateLimit.event_limit(:view_secret)).to eq(200)
        expect(V2::RateLimit.event_limit(:api_call)).to eq(1000)
      end

      it 'returns DEFAULT_LIMIT for unconfigured event' do
        expect(V2::RateLimit.event_limit(:unknown_event)).to eq(V2::RateLimit::DEFAULT_LIMIT)
      end
    end

    context 'when events are registered with symbol keys (legacy behavior)' do
      before(:each) do
        # Simulate legacy registration with symbol keys
        # Note: This is not the expected pattern - config should use string keys
        V2::RateLimit.register_events({
          create_secret: 50,
          view_secret: 200
        })
      end

      it 'does NOT find limit because lookup converts to string' do
        # The fix (commit 43ef9a7) converts event to string for lookup,
        # but symbol keys remain as symbols in the hash, so no match occurs.
        # This is expected behavior - config should always use string keys.
        expect(V2::RateLimit.event_limit(:create_secret)).to eq(V2::RateLimit::DEFAULT_LIMIT)
      end

      it 'does NOT find limit with string key either' do
        # String lookup against symbol key in hash doesn't match
        expect(V2::RateLimit.event_limit('create_secret')).to eq(V2::RateLimit::DEFAULT_LIMIT)
      end

      it 'demonstrates why string keys are required in config' do
        # This test documents the importance of the config change
        # Symbol keys won't match after the fix
        events = V2::RateLimit.events
        expect(events.keys.first).to be_a(Symbol)
        expect(events[:create_secret]).to eq(50)
        # But lookup converts to string, so it won't find it
        expect(events['create_secret']).to be_nil
      end
    end

    context 'key type consistency' do
      it 'converts symbol event to string for lookup' do
        V2::RateLimit.register_event('test_event', 42)
        # The fix ensures symbol lookups work with string-keyed events
        expect(V2::RateLimit.event_limit(:test_event)).to eq(42)
      end

      it 'handles string event directly' do
        V2::RateLimit.register_event('test_event', 42)
        expect(V2::RateLimit.event_limit('test_event')).to eq(42)
      end
    end
  end

  describe '.register_event' do
    it 'registers a single event with its limit' do
      V2::RateLimit.register_event('custom_event', 75)
      expect(V2::RateLimit.event_limit('custom_event')).to eq(75)
    end

    it 'overwrites existing event limit' do
      V2::RateLimit.register_event('custom_event', 75)
      V2::RateLimit.register_event('custom_event', 150)
      expect(V2::RateLimit.event_limit('custom_event')).to eq(150)
    end
  end

  describe '.register_events' do
    it 'registers multiple events at once' do
      V2::RateLimit.register_events({
        'event_a' => 10,
        'event_b' => 20,
        'event_c' => 30
      })

      expect(V2::RateLimit.event_limit('event_a')).to eq(10)
      expect(V2::RateLimit.event_limit('event_b')).to eq(20)
      expect(V2::RateLimit.event_limit('event_c')).to eq(30)
    end

    it 'merges with existing events' do
      V2::RateLimit.register_event('existing', 100)
      V2::RateLimit.register_events({ 'new_event' => 50 })

      expect(V2::RateLimit.event_limit('existing')).to eq(100)
      expect(V2::RateLimit.event_limit('new_event')).to eq(50)
    end
  end

  describe '.exceeded?' do
    before(:each) do
      V2::RateLimit.register_event('limited_event', 10)
    end

    it 'returns false when count is below limit' do
      expect(V2::RateLimit.exceeded?('limited_event', 5)).to be false
    end

    it 'returns false when count equals limit' do
      expect(V2::RateLimit.exceeded?('limited_event', 10)).to be false
    end

    it 'returns true when count exceeds limit' do
      expect(V2::RateLimit.exceeded?('limited_event', 11)).to be true
    end

    it 'uses DEFAULT_LIMIT for unconfigured events' do
      expect(V2::RateLimit.exceeded?('unconfigured', 100)).to be false
      expect(V2::RateLimit.exceeded?('unconfigured', 101)).to be true
    end

    it 'works with symbol event names' do
      expect(V2::RateLimit.exceeded?(:limited_event, 5)).to be false
      expect(V2::RateLimit.exceeded?(:limited_event, 11)).to be true
    end
  end

  describe '.events' do
    it 'returns the events hash' do
      V2::RateLimit.register_event('test', 42)
      expect(V2::RateLimit.events).to include('test' => 42)
    end

    it 'is initially empty' do
      expect(V2::RateLimit.events).to eq({})
    end
  end
end
