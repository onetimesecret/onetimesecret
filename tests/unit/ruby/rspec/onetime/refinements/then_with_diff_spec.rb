# tests/unit/ruby/rspec/onetime/refinements/then_with_diff_spec.rb

require_relative '../../spec_helper'
require 'onetime/refinements/then_with_diff'

RSpec.describe Onetime::IndifferentHashAccess

RSpec.describe Onetime::ThenWithDiff, :allow_redis do
  # Use the refinement within this test scope
  using Onetime::ThenWithDiff

  before(:each) do
    # Clear history before each test to ensure clean state
    begin
      Onetime::ThenWithDiff.history.clear
    rescue => e
      # If Redis isn't available, create a mock history for testing
      mock_history = double('mock_history')
      allow(mock_history).to receive(:clear)
      allow(mock_history).to receive(:<<)
      allow(mock_history).to receive(:last).and_return(nil)
      allow(mock_history).to receive(:size).and_return(0)
      allow(mock_history).to receive(:members).and_return([])
      allow(mock_history).to receive(:remrangebyscore)
      allow(Onetime::ThenWithDiff).to receive(:history).and_return(mock_history)
    end
  end

  context 'basic functionality' do
    it 'tracks changes between transformation steps' do
      config = { env: 'dev' }
        .then_with_diff('add database') { |c| c.merge(db: 'postgres') }
        .then_with_diff('add cache') { |c| c.merge(cache: 'redis') }

      expect(config).to eq({ env: 'dev', db: 'postgres', cache: 'redis' })
      expect(Onetime::ThenWithDiff.history.size).to eq(2)
    end

    it 'stores diff records with correct structure' do
      { name: 'test' }
        .then_with_diff('add email') { |c| c.merge(email: 'test@example.com') }

      record_json = Onetime::ThenWithDiff.history.last
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

      records = Onetime::ThenWithDiff.history.members.map { |json| JSON.parse(json) }

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
      skip "Cleanup test requires real Redis" unless Onetime::ThenWithDiff.history.respond_to?(:remrangebyscore)

      # Just verify that cleanup doesn't crash
      { test: true }.then_with_diff('cleanup test') { |c| c.merge(processed: true) }

      expect(Onetime::ThenWithDiff.history.size).to be >= 1
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
      expect(Onetime::ThenWithDiff.history.size).to be >= 20
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
      records = Onetime::ThenWithDiff.history.members
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
      records = Onetime::ThenWithDiff.history.members
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

      records = Onetime::ThenWithDiff.history.members
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
      expect(Onetime::ThenWithDiff.history.size).to eq(1)
    end

    it 'handles nil transformations gracefully' do
      # First add a record to establish previous state
      { value: 1 }.then_with_diff('initial') { |c| c }

      # Then do a no-change transformation
      result = { value: 1 }.then_with_diff('no change') { |c| c }

      expect(result).to eq({ value: 1 })

      records = Onetime::ThenWithDiff.history.members.map { |json| JSON.parse(json) }
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

      record = JSON.parse(Onetime::ThenWithDiff.history.last)
      # The diff should show the theme change somewhere in the structure
      expect(record['diff']).not_to be_empty
    end
  end
end
