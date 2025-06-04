# tests/unit/ruby/rspec/onetime/utils/deep_indifferent_hash_spec.rb

require_relative '../../spec_helper'

RSpec.describe Onetime::Utils do
  describe '#deep_indifferent_hash' do
    let(:subject) { described_class }

    context 'with flat hashes' do
      it 'creates hash with indifferent access' do
        hash = { 'name' => 'John', 'age' => 30 }
        result = subject.deep_indifferent_hash(hash)

        expect(result[:name]).to eq('John')
        expect(result['name']).to eq('John')
        expect(result[:age]).to eq(30)
        expect(result['age']).to eq(30)
      end

      it 'supports fetch with symbols on string-keyed hash' do
        hash = { 'name' => 'John', 'age' => 30 }
        result = subject.deep_indifferent_hash(hash)

        expect(result.fetch(:name)).to eq('John')
        expect(result.fetch('name')).to eq('John')
        expect(result.fetch(:age)).to eq(30)
        expect(result.fetch('age')).to eq(30)
      end

      it 'supports fetch with default values' do
        hash = { 'name' => 'John' }
        result = subject.deep_indifferent_hash(hash)

        expect(result.fetch(:missing, 'default')).to eq('default')
        expect(result.fetch('missing', 'default')).to eq('default')
      end

      it 'supports fetch with block' do
        hash = { 'name' => 'John' }
        result = subject.deep_indifferent_hash(hash)

        expect(result.fetch(:missing) { 'block_default' }).to eq('block_default')
        expect(result.fetch('missing') { 'block_default' }).to eq('block_default')
      end

      it 'raises KeyError for missing keys without default' do
        hash = { 'name' => 'John' }
        result = subject.deep_indifferent_hash(hash)

        expect { result.fetch(:missing) }.to raise_error(KeyError)
        expect { result.fetch('missing') }.to raise_error(KeyError)
      end
    end

    context 'with nested hashes' do
      it 'creates nested hashes with indifferent access' do
        hash = {
          'site' => {
            'secret' => 'abc123',
            'config' => {
              'timeout' => 30
            }
          }
        }
        result = subject.deep_indifferent_hash(hash)

        expect(result[:site][:secret]).to eq('abc123')
        expect(result['site']['secret']).to eq('abc123')
        expect(result[:site][:config][:timeout]).to eq(30)
        expect(result['site']['config']['timeout']).to eq(30)
      end

      it 'supports fetch on nested hashes' do
        hash = {
          'site' => {
            'secret' => 'abc123',
            'config' => {
              'timeout' => 30
            }
          }
        }
        result = subject.deep_indifferent_hash(hash)

        expect(result[:site].fetch(:secret)).to eq('abc123')
        expect(result.fetch('site').fetch('secret')).to eq('abc123')
        expect(result[:site][:config].fetch(:timeout)).to eq(30)
        expect(result.fetch('site').fetch('config').fetch('timeout')).to eq(30)
      end

      it 'handles deeply nested structures' do
        hash = {
          'a' => {
            'b' => {
              'c' => {
                'd' => 'deep_value'
              }
            }
          }
        }
        result = subject.deep_indifferent_hash(hash)

        expect(result[:a][:b][:c].fetch(:d)).to eq('deep_value')
        expect(result.fetch('a').fetch('b').fetch('c').fetch('d')).to eq('deep_value')
      end
    end

    context 'with arrays containing hashes' do
      it 'creates indifferent hashes within arrays' do
        hash = {
          'items' => [
            { 'name' => 'item1', 'value' => 100 },
            { 'name' => 'item2', 'value' => 200 }
          ]
        }
        result = subject.deep_indifferent_hash(hash)

        expect(result[:items][0][:name]).to eq('item1')
        expect(result['items'][0]['name']).to eq('item1')
        expect(result[:items][0].fetch(:value)).to eq(100)
        expect(result['items'][1].fetch('value')).to eq(200)
      end

      it 'handles nested arrays with hashes' do
        hash = {
          'matrix' => [
            [{ 'x' => 1, 'y' => 2 }],
            [{ 'x' => 3, 'y' => 4 }]
          ]
        }
        result = subject.deep_indifferent_hash(hash)

        expect(result[:matrix][0][0][:x]).to eq(1)
        expect(result['matrix'][1][0].fetch('y')).to eq(4)
      end
    end

    context 'with edge cases' do
      it 'handles empty hash' do
        result = subject.deep_indifferent_hash({})
        expect(result).to be_a(Hash)
        expect { result.fetch(:missing) }.to raise_error(KeyError)
      end

      it 'handles nil input' do
        result = subject.deep_indifferent_hash(nil)
        expect(result).to be_nil
      end

      it 'handles non-hash input' do
        result = subject.deep_indifferent_hash('string')
        expect(result).to eq('string')
      end

      it 'handles arrays' do
        array = [1, 2, { 'key' => 'value' }]
        result = subject.deep_indifferent_hash(array)

        expect(result).to be_a(Array)
        expect(result[2][:key]).to eq('value')
        expect(result[2].fetch(:key)).to eq('value')
      end
    end

    context 'demonstrating the bug this fixes' do
      it 'would fail without the deep_indifferent_hash fix' do
        # This test demonstrates that without proper recursive indifferent hash creation,
        # nested hashes lose their indifferent access behavior
        hash = { 'site' => { 'secret' => 'abc123' } }
        result = subject.deep_indifferent_hash(hash)

        # This would fail if deep_indifferent_hash didn't properly create
        # indifferent hashes recursively
        expect { result[:site].fetch(:secret) }.not_to raise_error
        expect(result[:site].fetch(:secret)).to eq('abc123')
      end

      it 'preserves indifferent access through multiple levels' do
        hash = {
          'config' => {
            'database' => {
              'host' => 'localhost',
              'port' => 5432,
              'settings' => {
                'timeout' => 30,
                'pool_size' => 10
              }
            }
          }
        }
        result = subject.deep_indifferent_hash(hash)

        # All these should work with the fix
        expect(result[:config][:database].fetch(:host)).to eq('localhost')
        expect(result.fetch('config').fetch('database').fetch('port')).to eq(5432)
        expect(result[:config][:database][:settings].fetch(:timeout)).to eq(30)
        expect(result['config']['database']['settings'].fetch('pool_size')).to eq(10)
      end

      it 'handles the real-world config scenario' do
        # This mirrors the actual usage in the config system
        merged_conf = { 'site' => { 'secret' => 'abc123', 'api' => { 'enabled' => true } } }
        conf = subject.deep_indifferent_hash(merged_conf)

        # These are the exact patterns used in the config code
        expect(conf.dig(:site, :secret)).to eq('abc123')
        expect(conf[:site].fetch(:secret)).to eq('abc123')
        expect(conf[:site][:api].fetch(:enabled)).to be true
      end
    end

    context 'with mixed key types in input' do
      it 'handles the post-deep_merge scenario with string keys' do
        # After deep_merge, all keys are strings - this tests the real scenario
        hash = { 'site' => { 'secret' => 'abc123', 'api' => { 'enabled' => true } } }
        result = subject.deep_indifferent_hash(hash)

        expect(result[:site].fetch(:secret)).to eq('abc123')
        expect(result['site'].fetch('secret')).to eq('abc123')
        expect(result[:site][:api].fetch(:enabled)).to be true
        expect(result['site']['api'].fetch('enabled')).to be true
      end
    end

    context 'immutability' do
      it 'does not mutate the original hash' do
        original = { 'site' => { 'secret' => 'abc123' } }
        original_copy = Marshal.load(Marshal.dump(original))

        subject.deep_indifferent_hash(original)

        expect(original).to eq(original_copy)
      end

      it 'does not mutate nested arrays' do
        original = { 'items' => [{ 'name' => 'test' }] }
        original_copy = Marshal.load(Marshal.dump(original))

        subject.deep_indifferent_hash(original)

        expect(original).to eq(original_copy)
      end
    end
  end
end
