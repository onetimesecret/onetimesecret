# spec/unit/onetime/utils/config_resolver_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Utils::ConfigResolver do
  describe '.defaults_path' do
    it 'returns the path when the defaults file exists' do
      path = described_class.defaults_path('config')
      skip 'No config.defaults.yaml found' unless path

      expect(path).to end_with('etc/defaults/config.defaults.yaml')
      expect(File.exist?(path)).to be true
    end

    it 'returns nil when no defaults file exists' do
      path = described_class.defaults_path('nonexistent')
      expect(path).to be_nil
    end
  end

end
