# spec/unit/onetime/utils/enumerables_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Utils::Enumerables do
  describe '.deep_merge preserve_nils parameter' do
    it 'preserves base value when override is nil (preserve_nils: true, default)' do
      base = { 'a' => 1, 'b' => 2 }
      override = { 'a' => nil, 'c' => 3 }
      result = described_class.deep_merge(base, override)
      expect(result['a']).to eq(1)
      expect(result['b']).to eq(2)
      expect(result['c']).to eq(3)
    end

    it 'allows nil override to win (preserve_nils: false)' do
      base = { 'a' => 1, 'b' => 2 }
      override = { 'b' => nil, 'c' => 3 }
      result = described_class.deep_merge(base, override, preserve_nils: false)
      expect(result['a']).to eq(1)
      expect(result['b']).to be_nil
      expect(result['c']).to eq(3)
    end

    it 'allows nil override in nested hashes (preserve_nils: false)' do
      base = { 'a' => { 'x' => 1, 'y' => 2 }, 'b' => 3 }
      override = { 'a' => { 'y' => nil, 'z' => 4 } }
      result = described_class.deep_merge(base, override, preserve_nils: false)
      expect(result['a']['x']).to eq(1)
      expect(result['a']['y']).to be_nil
      expect(result['a']['z']).to eq(4)
    end

    it 'produces different results for true vs false' do
      base = { 'a' => 1 }
      override = { 'a' => nil }
      with_preserve = described_class.deep_merge(base, override, preserve_nils: true)
      without_preserve = described_class.deep_merge(base, override, preserve_nils: false)
      expect(with_preserve['a']).to eq(1)
      expect(without_preserve['a']).to be_nil
    end
  end
end
