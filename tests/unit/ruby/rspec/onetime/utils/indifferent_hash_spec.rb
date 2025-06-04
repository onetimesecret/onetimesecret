# tests/unit/ruby/rspec/onetime/utils/indifferent_hash_spec.rb

require_relative '../../spec_helper'

RSpec.describe Onetime::Utils do
  describe '#indifferent_hash' do
    let(:subject) { described_class }

    context 'basic indifferent access' do
      it 'creates hash with symbol/string indifferent access via []' do
        hash = subject.send(:indifferent_hash)
        hash['name'] = 'John'

        expect(hash[:name]).to eq('John')
        expect(hash['name']).to eq('John')
      end

      it 'returns nil for missing keys via []' do
        hash = subject.send(:indifferent_hash)
        hash['name'] = 'John'

        expect(hash[:missing]).to be_nil
        expect(hash['missing']).to be_nil
      end
    end

    context 'fetch method with symbol/string conversion' do
      it 'supports fetch with symbols when keys are strings' do
        hash = subject.send(:indifferent_hash)
        hash['name'] = 'John'

        expect(hash.fetch(:name)).to eq('John')
        expect(hash.fetch('name')).to eq('John')
      end

      it 'raises KeyError for truly missing keys' do
        hash = subject.send(:indifferent_hash)
        hash['name'] = 'John'

        expect { hash.fetch(:missing) }.to raise_error(KeyError)
        expect { hash.fetch('missing') }.to raise_error(KeyError)
      end

      it 'supports fetch with default values' do
        hash = subject.send(:indifferent_hash)
        hash['name'] = 'John'

        expect(hash.fetch(:missing, 'default')).to eq('default')
        expect(hash.fetch('missing', 'default')).to eq('default')
      end
    end

    context 'demonstrating the bug this fixes' do
      it 'would fail without the fetch override' do
        # Without the fetch override, this would raise KeyError
        # even though the key exists as a string
        hash = subject.send(:indifferent_hash)
        hash['secret'] = 'abc123'

        # This is the exact scenario that was failing in the config system
        expect { hash.fetch(:secret) }.not_to raise_error
        expect(hash.fetch(:secret)).to eq('abc123')
      end

      it 'handles the real config scenario' do
        # Simulating the actual config usage pattern
        hash = subject.send(:indifferent_hash)
        hash['secret'] = 'abc123'

        expect { hash.fetch(:secret) }.not_to raise_error
        expect(hash.fetch(:secret)).to eq('abc123')
      end
    end
  end
end
