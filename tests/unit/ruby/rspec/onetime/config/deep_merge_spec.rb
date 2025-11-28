# tests/unit/ruby/rspec/onetime/config/deep_merge_spec.rb

require_relative '../../spec_helper'

RSpec.describe Onetime::Config do
  # Since deep_merge is private, we need to use send to test it directly
  # Note: deep_merge now returns an IndifferentHash with string keys internally.
  # We use a helper to compare values regardless of key type.
  describe '#deep_merge' do
    let(:subject) { described_class }

    # Helper to compare IndifferentHash result with expected values
    # IndifferentHash stores string keys internally, so we compare values via symbol access
    def values_match?(result, expected)
      return result == expected unless expected.is_a?(Hash)
      return false unless result.is_a?(Hash)
      return false unless result.keys.map(&:to_s).sort == expected.keys.map(&:to_s).sort

      expected.all? do |key, value|
        result_value = result[key.to_s] || result[key.to_sym]
        if value.is_a?(Hash)
          values_match?(result_value, value)
        else
          result_value == value
        end
      end
    end

    context 'with flat hashes' do
      it 'merges simple hashes correctly' do
        original = { a: 1, b: 2 }
        other = { b: 3, c: 4 }
        result = subject.send(:deep_merge, original, other)
        # IndifferentHash allows access via both symbol and string
        expect(result[:a]).to eq(1)
        expect(result[:b]).to eq(3)
        expect(result[:c]).to eq(4)
        expect(result['a']).to eq(1)  # String access should also work
      end

      it 'handles nil values in the second hash' do
        original = { a: 1, b: 2 }
        other = { b: nil, c: 3 }
        result = subject.send(:deep_merge, original, other)
        # nil in override preserves original value
        expect(result[:a]).to eq(1)
        expect(result[:b]).to eq(2)
        expect(result[:c]).to eq(3)
      end

      it 'preserves original hash' do
        original = { a: 1, b: 2 }
        other = { b: 3, c: 4 }
        original_dup = original.dup
        subject.send(:deep_merge, original, other)
        expect(original).to eq(original_dup)
      end

      it 'preserves override hash' do
        original = { a: 1, b: 2 }
        other = { b: 3, c: 4 }
        other_dup = other.dup
        subject.send(:deep_merge, original, other)
        expect(other).to eq(other_dup)
      end
    end

    context 'with nested hashes' do
      it 'deep merges nested hashes' do
        original = { a: { x: 1, y: 2 }, b: 3 }
        other = { a: { y: 3, z: 4 }, c: 5 }
        result = subject.send(:deep_merge, original, other)
        expect(result[:a][:x]).to eq(1)
        expect(result[:a][:y]).to eq(3)
        expect(result[:a][:z]).to eq(4)
        expect(result[:b]).to eq(3)
        expect(result[:c]).to eq(5)
      end

      it 'handles nil values in nested hashes' do
        original = { a: { x: 1, y: 2 }, b: 3 }
        other = { a: { y: nil, z: 4 }, c: 5 }
        result = subject.send(:deep_merge, original, other)
        expect(result[:a][:x]).to eq(1)
        expect(result[:a][:y]).to eq(2)  # nil preserves original
        expect(result[:a][:z]).to eq(4)
        expect(result[:b]).to eq(3)
        expect(result[:c]).to eq(5)
      end

      it 'handles deeply nested structures' do
        original = { a: { x: { p: 1, q: 2 }, y: 3 }, b: 4 }
        other = { a: { x: { q: 5, r: 6 }, z: 7 }, c: 8 }
        result = subject.send(:deep_merge, original, other)
        expect(result[:a][:x][:p]).to eq(1)
        expect(result[:a][:x][:q]).to eq(5)
        expect(result[:a][:x][:r]).to eq(6)
        expect(result[:a][:y]).to eq(3)
        expect(result[:a][:z]).to eq(7)
        expect(result[:b]).to eq(4)
        expect(result[:c]).to eq(8)
      end
    end

    context 'with edge cases' do
      it 'handles empty original hash' do
        original = {}
        other = { a: 1, b: 2 }
        result = subject.send(:deep_merge, original, other)
        expect(result[:a]).to eq(1)
        expect(result[:b]).to eq(2)
      end

      it 'handles empty override hash' do
        original = { a: 1, b: 2 }
        other = {}
        result = subject.send(:deep_merge, original, other)
        expect(result[:a]).to eq(1)
        expect(result[:b]).to eq(2)
      end

      it 'handles non-hash values in nested structures' do
        original = { a: { x: [1, 2], y: 'string' }, b: 3 }
        other = { a: { x: [3, 4], z: true }, c: nil }
        result = subject.send(:deep_merge, original, other)
        expect(result[:a][:x]).to eq([3, 4])
        expect(result[:a][:y]).to eq('string')
        expect(result[:a][:z]).to eq(true)
        expect(result[:b]).to eq(3)
        expect(result[:c]).to be_nil
      end

      it 'handles hash overriding non-hash value' do
        original = { a: 1 }
        other = { a: { x: 2 } }
        result = subject.send(:deep_merge, original, other)
        expect(result[:a][:x]).to eq(2)
      end

      it 'handles non-hash value overriding hash' do
        original = { a: { x: 1 } }
        other = { a: 2 }
        result = subject.send(:deep_merge, original, other)
        expect(result[:a]).to eq(2)
      end

      it 'handles nil original hash' do
        original = nil
        other = { a: 1 }
        expect { subject.send(:deep_merge, original, other) }.not_to raise_error
        result = subject.send(:deep_merge, original, other)
        expect(result[:a]).to eq(1)
      end

      it 'handles nil override hash' do
        original = { a: 1 }
        other = nil
        expect { subject.send(:deep_merge, original, other) }.not_to raise_error
        result = subject.send(:deep_merge, original, other)
        expect(result[:a]).to eq(1)
      end
    end

    context 'with complex real-world scenarios' do
      it 'correctly merges service configuration' do
        original = {
          environment: 'test',
          enabled: true,
          timeout: 30,
          retries: 3
        }

        other = {
          environment: 'production',
          timeout: nil,
          connection: {
            pool_size: 5,
            keep_alive: true
          }
        }

        result = subject.send(:deep_merge, original, other)
        expect(result[:environment]).to eq('production')
        expect(result[:enabled]).to eq(true)
        expect(result[:timeout]).to eq(30)  # nil preserves original
        expect(result[:retries]).to eq(3)
        expect(result[:connection][:pool_size]).to eq(5)
        expect(result[:connection][:keep_alive]).to eq(true)
      end

      it 'correctly handles deeply nested security configuration' do
        original = {
          site: {
            authentication: {
              enabled: true,
              methods: ['password', 'totp'],
              password: {
                min_length: 8,
                require_special: true
              }
            },
            ssl: {
              enabled: true,
              protocols: ['TLSv1.2', 'TLSv1.3']
            }
          }
        }

        other = {
          site: {
            authentication: {
              methods: ['password', 'saml'],
              password: {
                min_length: 12,
                max_age: 90
              },
              saml: {
                idp_url: 'https://example.com/saml'
              }
            },
            ssl: {
              protocols: ['TLSv1.3']
            },
            cors: {
              enabled: true,
              allowed_origins: ['example.com']
            }
          }
        }

        result = subject.send(:deep_merge, original, other)

        # Verify the merged structure using indifferent access
        expect(result[:site][:authentication][:enabled]).to eq(true)
        expect(result[:site][:authentication][:methods]).to eq(['password', 'saml'])
        expect(result[:site][:authentication][:password][:min_length]).to eq(12)
        expect(result[:site][:authentication][:password][:require_special]).to eq(true)
        expect(result[:site][:authentication][:password][:max_age]).to eq(90)
        expect(result[:site][:authentication][:saml][:idp_url]).to eq('https://example.com/saml')
        expect(result[:site][:ssl][:enabled]).to eq(true)
        expect(result[:site][:ssl][:protocols]).to eq(['TLSv1.3'])
        expect(result[:site][:cors][:enabled]).to eq(true)
        expect(result[:site][:cors][:allowed_origins]).to eq(['example.com'])
      end
    end

    context 'returns IndifferentHash' do
      it 'returns an IndifferentHash instance' do
        original = { a: 1, b: 2 }
        other = { b: 3, c: 4 }
        result = subject.send(:deep_merge, original, other)
        expect(result).to be_a(Onetime::IndifferentHash)
      end

      it 'nested hashes are also IndifferentHash' do
        original = { a: { x: 1 } }
        other = { a: { y: 2 } }
        result = subject.send(:deep_merge, original, other)
        expect(result[:a]).to be_a(Onetime::IndifferentHash)
      end

      it 'supports both symbol and string access on result' do
        original = { site: { host: 'example.com' } }
        other = { site: { port: 3000 } }
        result = subject.send(:deep_merge, original, other)

        # Symbol access
        expect(result[:site][:host]).to eq('example.com')
        expect(result[:site][:port]).to eq(3000)

        # String access
        expect(result['site']['host']).to eq('example.com')
        expect(result['site']['port']).to eq(3000)

        # Mixed access
        expect(result[:site]['host']).to eq('example.com')
        expect(result['site'][:port]).to eq(3000)
      end
    end
  end
end
