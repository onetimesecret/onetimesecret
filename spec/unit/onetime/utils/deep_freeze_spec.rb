# tests/unit/ruby/rspec/onetime/utils/deep_freeze_spec.rb

require_relative '../../spec_helper'

RSpec.describe Onetime::Utils do
  describe '#deep_freeze' do
    let(:subject) { described_class }

    context 'with simple objects' do
      it 'freezes simple objects' do
        string = 'test'
        result = subject.deep_freeze(string)

        expect(result).to be_frozen
        expect(result).to eq('test')
      end

      it 'freezes numeric objects' do
        number = 42
        result = subject.deep_freeze(number)

        expect(result).to be_frozen
        expect(result).to eq(42)
      end

      it 'handles nil' do
        result = subject.deep_freeze(nil)

        expect(result).to be_frozen
        expect(result).to be_nil
      end
    end

    context 'with flat hashes' do
      it 'freezes hash and all values' do
        hash = { 'name' => 'John', 'age' => 30 }
        result = subject.deep_freeze(hash)

        expect(result).to be_frozen
        expect(result['name']).to be_frozen
        expect(result['age']).to be_frozen
        expect(result).to eq({ 'name' => 'John', 'age' => 30 })
      end

      it 'prevents modification of frozen hash' do
        hash = { 'name' => 'John' }
        result = subject.deep_freeze(hash)

        expect { result['name'] = 'Jane' }.to raise_error(FrozenError)
        expect { result['new_key'] = 'value' }.to raise_error(FrozenError)
      end

      it 'prevents modification of frozen string values' do
        hash = { 'name' => 'John' }
        result = subject.deep_freeze(hash)

        expect { result['name'] << ' Doe' }.to raise_error(FrozenError)
        expect { result['name'].upcase! }.to raise_error(FrozenError)
      end
    end

    context 'with nested hashes' do
      it 'freezes nested hashes recursively' do
        hash = {
          'site' => {
            'secret' => 'abc123',
            'config' => {
              'timeout' => 30,
              'retries' => 3
            }
          }
        }
        result = subject.deep_freeze(hash)

        expect(result).to be_frozen
        expect(result['site']).to be_frozen
        expect(result['site']['secret']).to be_frozen
        expect(result['site']['config']).to be_frozen
        expect(result['site']['config']['timeout']).to be_frozen
        expect(result['site']['config']['retries']).to be_frozen
      end

      it 'prevents modification at any level' do
        hash = {
          'site' => {
            'secret' => 'abc123',
            'config' => { 'timeout' => 30 }
          }
        }
        result = subject.deep_freeze(hash)

        expect { result['site']['secret'] = 'new_secret' }.to raise_error(FrozenError)
        expect { result['site']['config']['timeout'] = 60 }.to raise_error(FrozenError)
        expect { result['site']['new_key'] = 'value' }.to raise_error(FrozenError)
      end

      it 'handles deeply nested structures' do
        hash = {
          'a' => {
            'b' => {
              'c' => {
                'd' => {
                  'e' => 'deep_value'
                }
              }
            }
          }
        }
        result = subject.deep_freeze(hash)

        expect(result['a']['b']['c']['d']).to be_frozen
        expect(result['a']['b']['c']['d']['e']).to be_frozen
        expect { result['a']['b']['c']['d']['e'] = 'new' }.to raise_error(FrozenError)
      end
    end

    context 'with arrays' do
      it 'freezes arrays and all elements' do
        array = ['item1', 'item2', 'item3']
        result = subject.deep_freeze(array)

        expect(result).to be_frozen
        expect(result[0]).to be_frozen
        expect(result[1]).to be_frozen
        expect(result[2]).to be_frozen
      end

      it 'prevents array modification' do
        array = ['item1', 'item2']
        result = subject.deep_freeze(array)

        expect { result << 'item3' }.to raise_error(FrozenError)
        expect { result[0] = 'new_item' }.to raise_error(FrozenError)
        expect { result.delete_at(0) }.to raise_error(FrozenError)
      end

      it 'prevents element modification' do
        array = ['mutable_string']
        result = subject.deep_freeze(array)

        expect { result[0] << '_suffix' }.to raise_error(FrozenError)
        expect { result[0].upcase! }.to raise_error(FrozenError)
      end
    end

    context 'with arrays containing hashes' do
      it 'freezes hashes within arrays' do
        array = [
          { 'name' => 'item1', 'value' => 100 },
          { 'name' => 'item2', 'value' => 200 }
        ]
        result = subject.deep_freeze(array)

        expect(result).to be_frozen
        expect(result[0]).to be_frozen
        expect(result[0]['name']).to be_frozen
        expect(result[0]['value']).to be_frozen
        expect(result[1]).to be_frozen
        expect(result[1]['name']).to be_frozen
        expect(result[1]['value']).to be_frozen
      end

      it 'prevents modification of nested structures' do
        array = [{ 'name' => 'item1' }]
        result = subject.deep_freeze(array)

        expect { result[0]['name'] = 'new_name' }.to raise_error(FrozenError)
        expect { result[0]['new_key'] = 'value' }.to raise_error(FrozenError)
      end
    end

    context 'with hashes containing arrays' do
      it 'freezes arrays within hashes' do
        hash = {
          'items' => ['item1', 'item2'],
          'config' => {
            'allowed_values' => [1, 2, 3]
          }
        }
        result = subject.deep_freeze(hash)

        expect(result['items']).to be_frozen
        expect(result['items'][0]).to be_frozen
        expect(result['items'][1]).to be_frozen
        expect(result['config']['allowed_values']).to be_frozen
        expect(result['config']['allowed_values'][0]).to be_frozen
      end

      it 'prevents array modification within hashes' do
        hash = { 'items' => ['item1'] }
        result = subject.deep_freeze(hash)

        expect { result['items'] << 'item2' }.to raise_error(FrozenError)
        expect { result['items'][0] = 'new_item' }.to raise_error(FrozenError)
      end
    end

    context 'with complex nested structures' do
      it 'handles mixed array and hash nesting' do
        complex = {
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
        result = subject.deep_freeze(complex)

        expect(result['matrix'][0][0]).to be_frozen
        expect(result['matrix'][0][0]['x']).to be_frozen
        expect(result['config']['nested_arrays'][0]).to be_frozen
        expect(result['config']['nested_arrays'][0][0]).to be_frozen
      end

      it 'prevents all modifications in complex structures' do
        complex = {
          'data' => [
            { 'items' => ['item1'] }
          ]
        }
        result = subject.deep_freeze(complex)

        expect { result['data'][0]['items'][0] = 'new' }.to raise_error(FrozenError)
        expect { result['data'][0]['items'] << 'item2' }.to raise_error(FrozenError)
        expect { result['data'][0]['new_key'] = 'value' }.to raise_error(FrozenError)
      end
    end

    context 'demonstrating security benefits' do
      it 'prevents configuration tampering after freezing' do
        config = {
          'site' => {
            'secret' => 'sensitive_key',
            'authentication' => {
              'enabled' => true,
              'methods' => ['password', 'totp']
            }
          }
        }
        frozen_config = subject.deep_freeze(config)

        # These would be security vulnerabilities if not prevented
        expect { frozen_config['site']['secret'] = 'hacked' }.to raise_error(FrozenError)
        expect { frozen_config['site']['authentication']['enabled'] = false }.to raise_error(FrozenError)
        expect { frozen_config['site']['authentication']['methods'] << 'backdoor' }.to raise_error(FrozenError)
      end

      it 'ensures configuration immutability throughout application lifecycle' do
        original_config = { 'sensitive' => 'data' }
        frozen_config = subject.deep_freeze(original_config)

        # deep_freeze modifies the original object in place
        expect(frozen_config).to be(original_config)
        expect(original_config).to be_frozen

        # Any attempt to modify should fail
        expect { frozen_config['sensitive'] = 'hack_attempt' }.to raise_error(FrozenError)
        expect { original_config['sensitive'] = 'hack_attempt' }.to raise_error(FrozenError)
      end
    end

    context 'edge cases' do
      it 'handles empty hash' do
        result = subject.deep_freeze({})

        expect(result).to be_frozen
        expect { result['new_key'] = 'value' }.to raise_error(FrozenError)
      end

      it 'handles empty array' do
        result = subject.deep_freeze([])

        expect(result).to be_frozen
        expect { result << 'item' }.to raise_error(FrozenError)
      end

      it 'handles already frozen objects' do
        already_frozen = { 'key' => 'value' }.freeze
        result = subject.deep_freeze(already_frozen)

        expect(result).to be_frozen
        expect(result['key']).to be_frozen
      end

      it 'returns the same object (frozen in place)' do
        original = { 'key' => 'value' }
        result = subject.deep_freeze(original)

        expect(result).to be(original)
        expect(original).to be_frozen
      end
    end

    context 'real-world configuration scenarios' do
      it 'freezes typical OneTimeSecret configuration' do
        config = {
          'site' => {
            'secret' => 'global_secret_key',
            'authentication' => {
              'enabled' => true,
              'colonels' => ['admin@example.com']
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
          }
        }

        frozen_config = subject.deep_freeze(config)

        # Verify complete immutability
        expect { frozen_config['site']['secret'] = 'compromised' }.to raise_error(FrozenError)
        expect { frozen_config['site']['authentication']['colonels'] << 'hacker' }.to raise_error(FrozenError)
        expect { frozen_config['site']['secret_options']['ttl_options'][0] = 1 }.to raise_error(FrozenError)
        expect { frozen_config['storage']['db']['connection']['url'] = 'evil://hack' }.to raise_error(FrozenError)
      end
    end
  end
end
