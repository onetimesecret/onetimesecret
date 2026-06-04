# spec/unit/onetime/utils/config_resolver_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Utils::ConfigResolver do
  describe '.defaults_path' do
    it 'returns the path when the defaults file exists' do
      path = described_class.defaults_path('config')
      expect(path).to end_with('etc/defaults/config.defaults.yaml')
      expect(File.exist?(path)).to be true
    end

    it 'returns nil when no defaults file exists' do
      path = described_class.defaults_path('nonexistent')
      expect(path).to be_nil
    end
  end

  describe '.resolve_stack' do
    it 'returns [defaults_path, override_path] for config' do
      stack = described_class.resolve_stack('config')
      expect(stack).to be_an(Array)
      expect(stack.length).to eq(2)
      expect(stack[0]).to end_with('config.defaults.yaml')
      expect(stack[1]).to end_with('config.test.yaml')
    end

    it 'returns [nil, nil] when neither file exists' do
      stack = described_class.resolve_stack('nonexistent')
      expect(stack).to eq([nil, nil])
    end

    it 'returns [defaults_path, nil] when only defaults exists and no override' do
      stack = described_class.resolve_stack('logging')
      if stack[0]
        expect(stack[0]).to end_with('logging.defaults.yaml')
      end
    end
  end
end
