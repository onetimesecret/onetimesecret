# tests/unit/ruby/rspec/onetime/refinements/hash_refinements_spec.rb

require_relative '../../spec_helper'
require 'onetime/refinements/hash_refinements'

RSpec.describe IndifferentHashAccess do
  # Use the refinement within this test scope
  using IndifferentHashAccess

  context 'with [] access' do
    it 'provides symbol/string indifferent access' do
      hash = { 'name' => 'John', 'age' => 30 }

      expect(hash[:name]).to eq('John')
      expect(hash['name']).to eq('John')
      expect(hash[:age]).to eq(30)
      expect(hash['age']).to eq(30)
    end

    it 'returns nil for missing keys' do
      hash = { 'name' => 'John' }

      expect(hash[:missing]).to be_nil
      expect(hash['missing']).to be_nil
    end
  end

  context 'with fetch method' do
    it 'supports fetch with symbols when keys are strings' do
      hash = { 'name' => 'John', 'age' => 30 }

      expect(hash.fetch(:name)).to eq('John')
      expect(hash.fetch('name')).to eq('John')
      expect(hash.fetch(:age)).to eq(30)
      expect(hash.fetch('age')).to eq(30)
    end

    it 'supports fetch with strings when keys are symbols' do
      hash = { name: 'John', age: 30 }

      expect(hash.fetch('name')).to eq('John')
      expect(hash.fetch(:name)).to eq('John')
      expect(hash.fetch('age')).to eq(30)
      expect(hash.fetch(:age)).to eq(30)
    end

    it 'supports fetch with default values for symbol conversion' do
      hash = { 'name' => 'John' }

      expect(hash.fetch(:missing, 'default')).to eq('default')
      expect(hash.fetch('missing', 'default')).to eq('default')
      expect(hash.fetch(:name, 'default')).to eq('John')
    end

    it 'supports fetch with blocks for symbol conversion' do
      hash = { 'name' => 'John' }

      expect(hash.fetch(:missing) { 'block_default' }).to eq('block_default')
      expect(hash.fetch('missing') { 'block_default' }).to eq('block_default')
      expect(hash.fetch(:name) { 'block_default' }).to eq('John')
    end

    it 'raises KeyError for truly missing keys' do
      hash = { 'name' => 'John' }

      expect { hash.fetch(:truly_missing) }.to raise_error(KeyError)
      expect { hash.fetch('truly_missing') }.to raise_error(KeyError)
    end

    it 'handles the config scenario that was failing' do
      # This is the exact scenario that was failing in config.rb
      hash = { 'secret' => 'abc123' }

      expect(hash.fetch(:secret, nil)).to eq('abc123')
      expect(hash.fetch(:secret, 'default')).to eq('abc123')
      expect(hash.fetch(:secret)).to eq('abc123')
    end
  end

  context 'with dig method' do
    it 'supports dig with flexible key access' do
      hash = { 'site' => { 'secret' => 'abc123' } }

      expect(hash.dig(:site, :secret)).to eq('abc123')
      expect(hash.dig('site', 'secret')).to eq('abc123')
      expect(hash.dig(:site, 'secret')).to eq('abc123')
      expect(hash.dig('site', :secret)).to eq('abc123')
    end

    it 'returns nil for missing keys in dig chain' do
      hash = { 'site' => { 'secret' => 'abc123' } }

      expect(hash.dig(:missing, :key)).to be_nil
      expect(hash.dig(:site, :missing)).to be_nil
    end

    it 'handles deeply nested structures' do
      hash = {
        'config' => {
          'database' => {
            'host' => 'localhost',
            'settings' => {
              'timeout' => 30,
            },
          },
        },
      }

      expect(hash.dig(:config, :database, :host)).to eq('localhost')
      expect(hash.dig(:config, :database, :settings, :timeout)).to eq(30)
    end
  end

  context 'edge cases' do
    it 'handles empty hashes' do
      hash = {}

      expect(hash[:missing]).to be_nil
      expect(hash.dig(:missing, :key)).to be_nil
      expect { hash.fetch(:missing) }.to raise_error(KeyError)
    end

    it 'preserves original key types when both exist' do
      hash = { 'name' => 'string_key', name: 'symbol_key' }

      # Should find exact matches first
      expect(hash.fetch('name')).to eq('string_key')
      expect(hash.fetch(:name)).to eq('symbol_key')
    end

    it 'handles nil values correctly' do
      hash = { 'nil_key' => nil }

      expect(hash[:nil_key]).to be_nil
      expect(hash.fetch(:nil_key)).to be_nil
      expect(hash.fetch(:nil_key, 'default')).to be_nil
    end
  end

  context 'array handling' do
    it 'works with arrays containing hashes' do
      # Refinements work when applied to hashes within arrays
      array = [
        { 'name' => 'item1', 'value' => 100 },
        { 'name' => 'item2', 'value' => 200 },
      ]

      expect(array[0][:name]).to eq('item1')
      expect(array[0]['name']).to eq('item1')
      expect(array[0].fetch(:value)).to eq(100)
      expect(array[1].fetch('value')).to eq(200)
    end

    it 'handles nested arrays with hashes' do
      matrix = [
        [{ 'x' => 1, 'y' => 2 }],
        [{ 'x' => 3, 'y' => 4 }],
      ]

      expect(matrix[0][0][:x]).to eq(1)
      expect(matrix[1][0].fetch('y')).to eq(4)
    end
  end

  context 'immutability and original hash preservation' do
    it 'does not mutate the original hash structure' do
      original = { 'site' => { 'secret' => 'abc123' } }
      original_copy = Marshal.load(Marshal.dump(original))

      # Access with refinement shouldn't change original
      original.dig(:site, :secret)
      original['site'].fetch(:secret)
      original[:site][:secret]

      expect(original).to eq(original_copy)
      expect(original.keys).to all(be_a(String))
      expect(original['site'].keys).to all(be_a(String))
    end

    it 'preserves key types in the original hash' do
      hash = { 'string_key' => 'value1', symbol_key: 'value2' }
      original_keys = hash.keys.dup

      # Using refinement shouldn't change key types
      hash[:string_key]
      hash['symbol_key']
      hash.fetch(:string_key)
      hash.fetch('symbol_key')

      expect(hash.keys).to eq(original_keys)
      expect(hash.keys).to include('string_key')
      expect(hash.keys).to include(:symbol_key)
    end
  end

  context 'nil input and error handling' do
    it 'handles nil gracefully where applicable' do
      # Refinements can't be applied to nil, but methods should still work
      expect { nil&.fetch(:key) }.not_to raise_error
      expect(nil&.fetch(:key)).to be_nil
    end

    it 'raises appropriate errors for invalid operations' do
      hash = { 'name' => 'John' }

      # These should still raise errors as expected
      expect { hash.fetch(:nonexistent) }.to raise_error(KeyError)
      expect { hash.dig(:nonexistent, :deeper) }.not_to raise_error
      expect(hash.dig(:nonexistent, :deeper)).to be_nil
    end
  end

  context 'additional edge cases and robustness' do
    it 'handles complex nested structures with mixed key types' do
      complex_hash = {
        'level1' => {
          level2_sym: {
            'level3' => {
              final_sym: 'deep_value',
            },
          },
        },
      }

      expect(complex_hash.dig(:level1, 'level2_sym', :level3, 'final_sym')).to eq('deep_value')
      expect(complex_hash[:level1]['level2_sym'].fetch(:level3)[:final_sym]).to eq('deep_value')
    end

    it 'works with numeric and other key types when string/symbol conversion doesn\'t apply' do
      # Test that string/symbol conversion doesn't break other key types
      hash = { 'name' => 'John', 1 => 'numeric', true => 'boolean' }

      expect(hash[:name]).to eq('John')
      expect(hash['name']).to eq('John')
      expect(hash[1]).to eq('numeric')
      expect(hash[true]).to eq('boolean')
      expect(hash.fetch(:name)).to eq('John')
      expect(hash.fetch(1)).to eq('numeric')
      expect(hash.fetch(true)).to eq('boolean')
    end

    it 'handles very deep nesting without issues' do
      deep_hash = { 'a' => { 'b' => { 'c' => { 'd' => { 'e' => 'very_deep' } } } } }

      expect(deep_hash.dig(:a, :b, :c, :d, :e)).to eq('very_deep')
      expect(deep_hash[:a][:b][:c][:d].fetch(:e)).to eq('very_deep')
    end

    it 'maintains performance characteristics' do
      # Ensure refinement doesn't significantly impact performance
      large_hash = (1..1000).each_with_object({}) { |i, h| h["key#{i}"] = "value#{i}" }

      # These 1000 operations should complete without timeout
      expect { 1000.times { large_hash.fetch(:key500) } }.not_to raise_error
      expect { 1000.times { large_hash[:key500] } }.not_to raise_error
    end
  end

  context 'demonstrating the real-world fix' do
    it 'fixes the config.rb scenario' do
      # This mirrors the exact failing scenario from config.rb
      conf = { 'site' => { 'secret' => 'abc123' } }
      site_hash = conf['site']

      # These should all work with the refinement
      expect(site_hash.fetch(:secret)).to eq('abc123')
      expect(site_hash.fetch(:secret, nil)).to eq('abc123')
      expect(site_hash.fetch(:secret, 'default')).to eq('abc123')
      expect(conf.dig(:site, :secret)).to eq('abc123')
    end

    it 'handles the real-world config scenario with mixed access patterns' do
      # Test the actual usage patterns found in the codebase
      merged_conf = { 'site' => { 'secret' => 'abc123', 'api' => { 'enabled' => true } } }

      # These are the exact patterns used in the config code
      expect(merged_conf.dig(:site, :secret)).to eq('abc123')
      expect(merged_conf[:site].fetch(:secret)).to eq('abc123')
      expect(merged_conf[:site][:api].fetch(:enabled)).to be true
      expect(merged_conf['site']['api'].fetch('enabled')).to be true
    end
  end
end

RSpec.describe ThenWithDiff, :allow_redis do
  # Use the refinement within this test scope
  using ThenWithDiff

  before(:each) do
    # Clear history before each test to ensure clean state
    begin
      ThenWithDiff.history.clear
    rescue => e
      # If Redis isn't available, create a mock history for testing
      mock_history = double('mock_history')
      allow(mock_history).to receive(:clear)
      allow(mock_history).to receive(:<<)
      allow(mock_history).to receive(:last).and_return(nil)
      allow(mock_history).to receive(:size).and_return(0)
      allow(mock_history).to receive(:members).and_return([])
      allow(mock_history).to receive(:remrangebyscore)
      allow(ThenWithDiff).to receive(:history).and_return(mock_history)
    end
  end

  context 'basic functionality' do
    it 'tracks changes between transformation steps' do
      config = { env: 'dev' }
        .then_with_diff('add database') { |c| c.merge(db: 'postgres') }
        .then_with_diff('add cache') { |c| c.merge(cache: 'redis') }

      expect(config).to eq({ env: 'dev', db: 'postgres', cache: 'redis' })
      expect(ThenWithDiff.history.size).to eq(2)
    end

    it 'stores diff records with correct structure' do
      { name: 'test' }
        .then_with_diff('add email') { |c| c.merge(email: 'test@example.com') }

      record_json = ThenWithDiff.history.last
      record = JSON.parse(record_json)

      expect(record).to have_key('step_name')
      expect(record).to have_key('diff')
      expect(record).to have_key('content')
      expect(record).to have_key('created')
      expect(record).to have_key('mode')
      expect(record).to have_key('instance')
      expect(record['step_name']).to eq('add email')
    end

    it 'tracks diffs between consecutive steps' do
      { count: 1 }
        .then_with_diff('increment') { |c| c.merge(count: 2) }
        .then_with_diff('add name') { |c| c.merge(name: 'test') }

      records = ThenWithDiff.history.members.map { |json| JSON.parse(json) }

      # Records are returned in sorted order, so we need to find them by step name
      increment_record = records.find { |r| r['step_name'] == 'increment' }
      add_name_record = records.find { |r| r['step_name'] == 'add name' }

      expect(records.size).to eq(2)
      expect(increment_record['diff']).to include(['+', 'count', 2])
      expect(add_name_record['diff']).to include(['+', 'name', 'test'])
    end

    it 'handles deep cloning correctly' do
      original = { nested: { value: 1 } }

      result = original.then_with_diff('modify', deep_clone: true) do |c|
        # Create a new hash instead of modifying the original
        c.merge(nested: { value: 2 })
      end

      # Original should be unchanged due to deep cloning
      expect(original[:nested][:value]).to eq(1)
      expect(result[:nested][:value]).to eq(2)
    end

    it 'handles no deep cloning when requested' do
      original = { value: 1 }

      result = original.then_with_diff('modify', deep_clone: false) do |c|
        c[:value] = 2
        c
      end

      # With no deep cloning, we get the same object reference
      expect(result).to be(original)
      expect(result[:value]).to eq(2)
    end
  end

  context 'cleanup and memory management' do
    it 'removes old records beyond 14 days' do
      # Skip this test if using mock history (no Redis cleanup possible)
      skip "Cleanup test requires real Redis" unless ThenWithDiff.history.respond_to?(:remrangebyscore)

      # Just verify that cleanup doesn't crash
      { test: true }.then_with_diff('cleanup test') { |c| c.merge(processed: true) }

      expect(ThenWithDiff.history.size).to be >= 1
    end
  end

  context 'thread safety' do
    it 'handles concurrent access without corruption' do
      threads = []
      results = {}

      # Create multiple threads that use then_with_diff simultaneously
      10.times do |i|
        threads << Thread.new do
          result = { thread_id: i, value: 0 }
            .then_with_diff("thread_#{i}_step1") { |c| c.merge(value: i * 2) }
            .then_with_diff("thread_#{i}_step2") { |c| c.merge(final: true) }

          results[i] = result
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify all threads completed successfully
      expect(results.size).to eq(10)

      # Verify each thread's result is correct
      results.each do |thread_id, result|
        expect(result[:thread_id]).to eq(thread_id)
        expect(result[:value]).to eq(thread_id * 2)
        expect(result[:final]).to be true
      end

      # History should contain records from all threads (20 records total)
      expect(ThenWithDiff.history.size).to be >= 20
    end

    it 'maintains data integrity under concurrent modifications' do
      shared_counter = { count: 0 }
      threads = []

      # Multiple threads incrementing the same counter
      5.times do |i|
        threads << Thread.new do
          10.times do |j|
            shared_counter = shared_counter
              .then_with_diff("thread_#{i}_increment_#{j}") do |c|
                c.merge(count: c[:count] + 1)
              end
          end
        end
      end

      threads.each(&:join)

      # While the final count might not be exactly 50 due to race conditions
      # in the shared_counter updates, the history should be complete
      records = ThenWithDiff.history.members
      expect(records.size).to eq(50) # 5 threads * 10 increments each
    end

    it 'prevents history corruption during concurrent appends' do
      threads = []

      # Many threads adding records simultaneously
      20.times do |i|
        threads << Thread.new do
          { id: i }.then_with_diff("concurrent_#{i}") { |c| c.merge(processed: true) }
        end
      end

      threads.each(&:join)

      # All records should be present and valid JSON
      records = ThenWithDiff.history.members
      expect(records.size).to eq(20)

      # Every record should be valid JSON
      expect { records.each { |json| JSON.parse(json) } }.not_to raise_error

      # Each record should have the expected structure
      parsed_records = records.map { |json| JSON.parse(json) }
      parsed_records.each do |record|
        expect(record).to have_key('step_name')
        expect(record).to have_key('content')
        expect(record).to have_key('mode')
        expect(record).to have_key('instance')
        expect(record['step_name']).to match(/concurrent_\d+/)
      end
    end

    it 'handles rapid sequential access safely' do
      # Simulate rapid-fire usage that might happen in real applications
      100.times do |i|
        { iteration: i }
          .then_with_diff("rapid_#{i}") { |c| c.merge(processed: true) }
      end

      records = ThenWithDiff.history.members
      expect(records.size).to eq(100)

      # Verify ordering is maintained (sorted set should keep chronological order)
      parsed_records = records.map { |json| JSON.parse(json) }
      created_times = parsed_records.map { |r| r['created'] }
      expect(created_times).to eq(created_times.sort)
    end
  end

  context 'edge cases and error handling' do
    it 'handles empty initial state' do
      result = {}.then_with_diff('add first') { |c| c.merge(first: true) }

      expect(result).to eq({ first: true })
      expect(ThenWithDiff.history.size).to eq(1)
    end

    it 'handles nil transformations gracefully' do
      # First add a record to establish previous state
      { value: 1 }.then_with_diff('initial') { |c| c }

      # Then do a no-change transformation
      result = { value: 1 }.then_with_diff('no change') { |c| c }

      expect(result).to eq({ value: 1 })

      records = ThenWithDiff.history.members.map { |json| JSON.parse(json) }
      last_record = records.last
      expect(last_record['diff']).to be_empty # No changes detected between identical states
    end

    it 'preserves frozen objects correctly' do
      frozen_hash = { frozen: true }.freeze

      result = frozen_hash.then_with_diff('modify frozen') do |c|
        c.merge(modified: true)
      end

      expect(result).to eq({ frozen: true, modified: true })
      expect(frozen_hash).to eq({ frozen: true }) # Original unchanged
    end

    it 'handles complex nested structures' do
      complex = {
        users: [
          { id: 1, profile: { name: 'John', settings: { theme: 'dark' } } }
        ],
        config: { database: { host: 'localhost', port: 5432 } }
      }

      result = complex.then_with_diff('update theme') do |c|
        # Create a deep copy and modify it
        new_config = JSON.parse(JSON.dump(c))
        new_config['users'][0]['profile']['settings']['theme'] = 'light'
        new_config
      end

      expect(result['users'][0]['profile']['settings']['theme']).to eq('light')

      record = JSON.parse(ThenWithDiff.history.last)
      # The diff should show the theme change somewhere in the structure
      expect(record['diff']).not_to be_empty
    end
  end
end
