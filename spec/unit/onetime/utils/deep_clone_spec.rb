# tests/unit/ruby/rspec/onetime/utils/deep_clone_spec.rb

require_relative '../../../spec_helper'

RSpec.describe Onetime::Utils do
  describe '#deep_clone' do
    let(:subject) { described_class }

    context 'with simple objects' do
      it 'clones simple strings' do
        original = 'test_string'
        result = subject.send(:deep_clone, original)

        expect(result).to eq('test_string')
        expect(result).not_to be(original)
      end

      it 'clones numbers' do
        original = 42
        result = subject.send(:deep_clone, original)

        expect(result).to eq(42)
        expect(result).to be(original) # Numbers are immutable
      end

      it 'handles nil' do
        result = subject.send(:deep_clone, nil)
        expect(result).to be_nil
      end

      it 'handles booleans' do
        expect(subject.send(:deep_clone, true)).to be true
        expect(subject.send(:deep_clone, false)).to be false
      end
    end

    context 'with flat hashes' do
      it 'creates independent copy of hash' do
        original = { 'name' => 'John', 'age' => 30 }
        result = subject.send(:deep_clone, original)

        expect(result).to eq(original)
        expect(result).not_to be(original)
      end

      it 'allows independent modification' do
        original = { 'name' => 'John', 'age' => 30 }
        result = subject.send(:deep_clone, original)

        result['name'] = 'Jane'
        result['city'] = 'NYC'

        expect(original['name']).to eq('John')
        expect(original).not_to have_key('city')
        expect(result['name']).to eq('Jane')
        expect(result['city']).to eq('NYC')
      end

      it 'clones string values independently' do
        original = { 'message' => 'hello' }
        result = subject.send(:deep_clone, original)

        result['message'] << ' world'

        expect(original['message']).to eq('hello')
        expect(result['message']).to eq('hello world')
      end
    end

    context 'with nested hashes' do
      it 'creates deep independent copy' do
        original = {
          'site' => {
            'secret' => 'abc123',
            'config' => {
              'timeout' => 30,
              'retries' => 3
            }
          }
        }
        result = subject.send(:deep_clone, original)

        expect(result).to eq(original)
        expect(result).not_to be(original)
        expect(result['site']).not_to be(original['site'])
        expect(result['site']['config']).not_to be(original['site']['config'])
      end

      it 'allows independent nested modifications' do
        original = {
          'site' => {
            'secret' => 'abc123',
            'config' => { 'timeout' => 30 }
          }
        }
        result = subject.send(:deep_clone, original)

        result['site']['secret'] = 'new_secret'
        result['site']['config']['timeout'] = 60
        result['site']['new_key'] = 'new_value'

        expect(original['site']['secret']).to eq('abc123')
        expect(original['site']['config']['timeout']).to eq(30)
        expect(original['site']).not_to have_key('new_key')
      end

      it 'handles deeply nested structures' do
        original = {
          'a' => {
            'b' => {
              'c' => {
                'd' => 'deep_value'
              }
            }
          }
        }
        result = subject.send(:deep_clone, original)

        result['a']['b']['c']['d'] = 'modified'

        expect(original['a']['b']['c']['d']).to eq('deep_value')
        expect(result['a']['b']['c']['d']).to eq('modified')
      end
    end

    context 'with arrays' do
      it 'creates independent copy of arrays' do
        original = ['item1', 'item2', 'item3']
        result = subject.send(:deep_clone, original)

        expect(result).to eq(original)
        expect(result).not_to be(original)
      end

      it 'allows independent array modifications' do
        original = ['item1', 'item2']
        result = subject.send(:deep_clone, original)

        result << 'item3'
        result[0] = 'modified_item1'

        expect(original).to eq(['item1', 'item2'])
        expect(result).to eq(['modified_item1', 'item2', 'item3'])
      end

      it 'clones array elements independently' do
        original = ['mutable_string']
        result = subject.send(:deep_clone, original)

        result[0] << '_suffix'

        expect(original[0]).to eq('mutable_string')
        expect(result[0]).to eq('mutable_string_suffix')
      end
    end

    context 'with arrays containing hashes' do
      it 'creates independent copies of nested hashes' do
        original = [
          { 'name' => 'item1', 'value' => 100 },
          { 'name' => 'item2', 'value' => 200 }
        ]
        result = subject.send(:deep_clone, original)

        expect(result).to eq(original)
        expect(result).not_to be(original)
        expect(result[0]).not_to be(original[0])
        expect(result[1]).not_to be(original[1])
      end

      it 'allows independent modification of nested hashes' do
        original = [{ 'name' => 'item1', 'value' => 100 }]
        result = subject.send(:deep_clone, original)

        result[0]['name'] = 'modified_item'
        result[0]['new_key'] = 'new_value'

        expect(original[0]['name']).to eq('item1')
        expect(original[0]).not_to have_key('new_key')
        expect(result[0]['name']).to eq('modified_item')
        expect(result[0]['new_key']).to eq('new_value')
      end
    end

    context 'with hashes containing arrays' do
      it 'creates independent copies of nested arrays' do
        original = {
          'items' => ['item1', 'item2'],
          'config' => {
            'allowed_values' => [1, 2, 3]
          }
        }
        result = subject.send(:deep_clone, original)

        expect(result['items']).not_to be(original['items'])
        expect(result['config']['allowed_values']).not_to be(original['config']['allowed_values'])
      end

      it 'allows independent modification of nested arrays' do
        original = { 'items' => ['item1'] }
        result = subject.send(:deep_clone, original)

        result['items'] << 'item2'
        result['items'][0] = 'modified_item1'

        expect(original['items']).to eq(['item1'])
        expect(result['items']).to eq(['modified_item1', 'item2'])
      end
    end

    context 'with complex nested structures' do
      it 'handles mixed array and hash nesting' do
        original = {
          'matrix' => [
            [{ 'x' => 1, 'y' => 2 }],
            [{ 'x' => 3, 'y' => 4 }]
          ],
          'config' => {
            'nested_arrays' => [
              ['a', 'b'],
              ['c', 'd']
            ]
          }
        }
        result = subject.send(:deep_clone, original)

        result['matrix'][0][0]['x'] = 999
        result['config']['nested_arrays'][0][0] = 'modified'

        expect(original['matrix'][0][0]['x']).to eq(1)
        expect(original['config']['nested_arrays'][0][0]).to eq('a')
        expect(result['matrix'][0][0]['x']).to eq(999)
        expect(result['config']['nested_arrays'][0][0]).to eq('modified')
      end
    end

    context 'with symbol keys' do
      it 'preserves symbol keys' do
        original = { name: 'John', age: 30 }
        result = subject.send(:deep_clone, original)

        expect(result).to eq(original)
        expect(result.keys).to all(be_a(Symbol))
        expect(result).not_to be(original)
      end

      it 'handles mixed symbol and string keys' do
        original = { 'name' => 'John', age: 30 }
        result = subject.send(:deep_clone, original)

        expect(result).to eq(original)
        expect(result).to have_key('name')
        expect(result).to have_key(:age)
      end

      it 'preserves symbol keys in nested structures' do
        original = { user: { name: 'John', 'details' => { age: 30 } } }
        result = subject.send(:deep_clone, original)

        expect(result[:user][:name]).to eq('John')
        expect(result[:user]['details'][:age]).to eq(30)
      end
    end

    context 'preventing mutation propagation' do
      it 'prevents configuration mutations from affecting multiple components' do
        shared_config = {
          'database' => {
            'host' => 'localhost',
            'settings' => ['setting1', 'setting2']
          }
        }

        component_a_config = subject.send(:deep_clone, shared_config)
        component_b_config = subject.send(:deep_clone, shared_config)

        # Component A modifies its config
        component_a_config['database']['host'] = 'remote_host'
        component_a_config['database']['settings'] << 'setting3'

        # Component B should be unaffected
        expect(component_b_config['database']['host']).to eq('localhost')
        expect(component_b_config['database']['settings']).to eq(['setting1', 'setting2'])

        # Original should also be unaffected
        expect(shared_config['database']['host']).to eq('localhost')
        expect(shared_config['database']['settings']).to eq(['setting1', 'setting2'])
      end
    end

    context 'error handling' do
      it 'raises OT::Problem for YAML serialization failures' do
        # Create an object that cannot be YAML serialized safely
        unserializable = Object.new

        expect { subject.send(:deep_clone, unserializable) }.to raise_error(OT::Problem)
      end

      it 'handles basic serializable objects' do
        # Test with objects that can be YAML serialized
        simple_hash = { 'test' => 'value', 'number' => 42 }
        result = subject.send(:deep_clone, simple_hash)

        expect(result).to eq(simple_hash)
        expect(result).not_to be(simple_hash)
      end
    end

    context 'edge cases' do
      it 'handles empty hash' do
        result = subject.send(:deep_clone, {})

        expect(result).to eq({})
        expect(result).not_to be({}) # Different empty hash instance
      end

      it 'handles empty array' do
        result = subject.send(:deep_clone, [])

        expect(result).to eq([])
        expect(result).not_to be([]) # Different empty array instance
      end

      it 'handles hash with nil values' do
        original = { 'key1' => nil, 'key2' => 'value' }
        result = subject.send(:deep_clone, original)

        expect(result).to eq(original)
        expect(result).not_to be(original)
      end

      it 'handles array with nil values' do
        original = [nil, 'value', nil]
        result = subject.send(:deep_clone, original)

        expect(result).to eq(original)
        expect(result).not_to be(original)
      end
    end

    context 'real-world configuration scenarios' do
      it 'clones typical OneTimeSecret configuration safely' do
        config = {
          'site' => {
            'secret' => 'global_secret_key',
            'authentication' => {
              'enabled' => true,
              'colonels' => ['admin@example.com', 'super@example.com']
            },
            'secret_options' => {
              'ttl_options' => [3600, 86400, 604800],
              'default_ttl' => 3600
            }
          },
          'storage' => {
            'db' => {
              'connection' => {
                'url' => 'redis://localhost:6379'
              }
            }
          },
          'experimental' => {
            'features' => ['feature_a', 'feature_b']
          }
        }

        # Simulate different parts of application getting their own config copies
        web_config = subject.send(:deep_clone, config)
        api_config = subject.send(:deep_clone, config)

        # Web component modifies its config
        web_config['site']['secret'] = 'web_specific_secret'
        web_config['site']['authentication']['colonels'] << 'web_admin@example.com'
        web_config['experimental']['features'] << 'web_feature'

        # API component modifies its config
        api_config['storage']['db']['connection']['url'] = 'redis://api_host:6379'
        api_config['site']['secret_options']['ttl_options'][0] = 1800

        # Original config should be unchanged
        expect(config['site']['secret']).to eq('global_secret_key')
        expect(config['site']['authentication']['colonels']).to eq(['admin@example.com', 'super@example.com'])
        expect(config['storage']['db']['connection']['url']).to eq('redis://localhost:6379')
        expect(config['site']['secret_options']['ttl_options'][0]).to eq(3600)
        expect(config['experimental']['features']).to eq(['feature_a', 'feature_b'])

        # Each component should have its own changes
        expect(web_config['site']['secret']).to eq('web_specific_secret')
        expect(web_config['site']['authentication']['colonels']).to include('web_admin@example.com')
        expect(web_config['experimental']['features']).to include('web_feature')

        expect(api_config['storage']['db']['connection']['url']).to eq('redis://api_host:6379')
        expect(api_config['site']['secret_options']['ttl_options'][0]).to eq(1800)

        # Components should not affect each other
        expect(api_config['site']['secret']).to eq('global_secret_key')
        expect(web_config['storage']['db']['connection']['url']).to eq('redis://localhost:6379')
      end

      it 'demonstrates the bug this method prevents' do
        # Without deep cloning, this would be a problematic scenario
        shared_defaults = {
          'timeouts' => [30, 60, 90],
          'settings' => { 'retry_count' => 3 }
        }

        # If we used shallow copying (assignment), mutations would propagate
        service_a_config = subject.send(:deep_clone, shared_defaults)
        service_b_config = subject.send(:deep_clone, shared_defaults)

        # Service A needs different timeouts
        service_a_config['timeouts'][0] = 10
        service_a_config['settings']['retry_count'] = 5

        # Service B should maintain original values
        expect(service_b_config['timeouts'][0]).to eq(30)
        expect(service_b_config['settings']['retry_count']).to eq(3)

        # This demonstrates that deep_clone prevents unintended side effects
        # that would occur with shallow copying or reference sharing
      end
    end

    context 'performance considerations' do
      it 'handles reasonably large configurations' do
        large_config = {}
        100.times do |i|
          large_config["section_#{i}"] = {
            'enabled' => true,
            'data' => (1..50).to_a,
            'nested' => {
              'values' => (1..20).map { |j| "value_#{j}" }
            }
          }
        end

        expect { subject.send(:deep_clone, large_config) }.not_to raise_error

        result = subject.send(:deep_clone, large_config)
        expect(result).to eq(large_config)
        expect(result).not_to be(large_config)
      end
    end
  end
end
