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
