# spec/onetime/config/deep_merge_spec.rb

require_relative '../../spec_helper'

RSpec.describe Onetime::Config do
  # Since deep_merge is private, we need to use send to test it directly
  describe '#deep_merge' do
    let(:subject) { described_class }

    context 'with flat hashes' do
      it 'merges simple hashes correctly' do
        original = { a: 1, b: 2 }
        other = { b: 3, c: 4 }
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: 1, b: 3, c: 4 })
      end

      it 'handles nil values in the second hash' do
        original = { a: 1, b: 2 }
        other = { b: nil, c: 3 }
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: 1, b: 2, c: 3 })
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
        expect(result).to eq({ a: { x: 1, y: 3, z: 4 }, b: 3, c: 5 })
      end

      it 'handles nil values in nested hashes' do
        original = { a: { x: 1, y: 2 }, b: 3 }
        other = { a: { y: nil, z: 4 }, c: 5 }
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: { x: 1, y: 2, z: 4 }, b: 3, c: 5 })
      end

      it 'handles deeply nested structures' do
        original = { a: { x: { p: 1, q: 2 }, y: 3 }, b: 4 }
        other = { a: { x: { q: 5, r: 6 }, z: 7 }, c: 8 }
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: { x: { p: 1, q: 5, r: 6 }, y: 3, z: 7 }, b: 4, c: 8 })
      end
    end

    context 'with edge cases' do
      it 'handles empty original hash' do
        original = {}
        other = { a: 1, b: 2 }
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: 1, b: 2 })
      end

      it 'handles empty override hash' do
        original = { a: 1, b: 2 }
        other = {}
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: 1, b: 2 })
      end

      it 'handles non-hash values in nested structures' do
        original = { a: { x: [1, 2], y: 'string' }, b: 3 }
        other = { a: { x: [3, 4], z: true }, c: nil }
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: { x: [3, 4], y: 'string', z: true }, b: 3, c: nil })
      end

      it 'handles hash overriding non-hash value' do
        original = { a: 1 }
        other = { a: { x: 2 } }
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: { x: 2 } })
      end

      it 'handles non-hash value overriding hash' do
        original = { a: { x: 1 } }
        other = { a: 2 }
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: 2 })
      end

      it 'handles nil original hash' do
        original = nil
        other = { a: 1 }
        expect { subject.send(:deep_merge, original, other) }.not_to raise_error
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: 1 })
      end

      it 'handles nil override hash' do
        original = { a: 1 }
        other = nil
        expect { subject.send(:deep_merge, original, other) }.not_to raise_error
        result = subject.send(:deep_merge, original, other)
        expect(result).to eq({ a: 1 })
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

        expected = {
          environment: 'production',
          enabled: true,
          timeout: 30,
          retries: 3,
          connection: {
            pool_size: 5,
            keep_alive: true
          }
        }

        result = subject.send(:deep_merge, original, other)
        expect(result).to eq(expected)
      end

      it 'correctly handles deeply nested security configuration' do
        original = {
          'site' => {
            'authentication' => {
              'enabled' => true,
              'methods' => ['password', 'totp'],
              'password' => {
                'min_length' => 8,
                'require_special' => true
              }
            },
            'ssl' => {
              'enabled' => true,
              'protocols' => ['TLSv1.2', 'TLSv1.3']
            }
          }
        }

        other = {
          'site' => {
            'authentication' => {
              'methods' => ['password', 'saml'],
              'password' => {
                'min_length' => 12,
                'max_age' => 90
              },
              'saml' => {
                'idp_url' => 'https://example.com/saml'
              }
            },
            'ssl' => {
              'protocols' => ['TLSv1.3']
            },
            'cors' => {
              'enabled' => true,
              'allowed_origins' => ['example.com']
            }
          }
        }

        expected = {
          'site' => {
            'authentication' => {
              'enabled' => true,
              'methods' => ['password', 'saml'],
              'password' => {
                'min_length' => 12,
                'require_special' => true,
                'max_age' => 90
              },
              'saml' => {
                'idp_url' => 'https://example.com/saml'
              }
            },
            'ssl' => {
              'enabled' => true,
              'protocols' => ['TLSv1.3']
            },
            'cors' => {
              'enabled' => true,
              'allowed_origins' => ['example.com']
            }
          }
        }

        result = subject.send(:deep_merge, original, other)
        expect(result).to eq(expected)
      end
    end
  end
end
