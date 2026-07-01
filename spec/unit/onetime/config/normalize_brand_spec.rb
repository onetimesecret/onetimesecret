# spec/unit/onetime/config/normalize_brand_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Config do
  describe '.normalize_brand' do
    # Render only matters as the "fallback" layer; these specs exercise the
    # Ruby normalization that is now the authority for the brand block.
    def normalized(conf, env)
      # Strip any ambient BRAND_* (sourced from .env) so each case is isolated.
      base = ENV.to_h.reject { |k, _| k.start_with?('BRAND_') }
      stub_const('ENV', base.merge(env))
      described_class.normalize_brand(conf)
      conf['brand']
    end

    it 'recovers a hex primary_color that the YAML layer drops to nil' do
      # Leading '#' makes `primary_color: #fff` a YAML comment -> nil. The env
      # read in normalize_brand restores the real value.
      brand = normalized({ 'brand' => { 'primary_color' => nil } },
                         'BRAND_PRIMARY_COLOR' => '#3B82F6')
      expect(brand['primary_color']).to eq('#3B82F6')
    end

    it 'preserves values containing quotes without YAML escaping' do
      brand = normalized({ 'brand' => {} }, 'BRAND_PRODUCT_NAME' => "O'Brien's App")
      expect(brand['product_name']).to eq("O'Brien's App")
    end

    it 'trims surrounding whitespace and maps blank env to nil' do
      brand = normalized({ 'brand' => {} },
                         'BRAND_LOGO_URL' => '  https://cdn.example.com/l.svg  ',
                         'BRAND_SUPPORT_EMAIL' => '   ')
      expect(brand['logo_url']).to eq('https://cdn.example.com/l.svg')
      expect(brand['support_email']).to be_nil
    end

    it 'leaves a YAML-supplied value intact when the env var is unset' do
      brand = normalized({ 'brand' => { 'product_name' => 'Direct YAML' } }, {})
      expect(brand['product_name']).to eq('Direct YAML')
    end

    context 'button_text_light' do
      it 'is nil when unset' do
        expect(normalized({ 'brand' => {} }, {})['button_text_light']).to be_nil
      end

      it 'is false only for an explicit false' do
        expect(normalized({ 'brand' => {} }, 'BRAND_BUTTON_TEXT_LIGHT' => 'false')['button_text_light']).to be(false)
      end

      it 'is true for any other set value' do
        expect(normalized({ 'brand' => {} }, 'BRAND_BUTTON_TEXT_LIGHT' => 'true')['button_text_light']).to be(true)
        expect(normalized({ 'brand' => {} }, 'BRAND_BUTTON_TEXT_LIGHT' => 'light')['button_text_light']).to be(true)
      end

      it 'coerces a YAML-parsed boolean false when the env var is unset' do
        expect(normalized({ 'brand' => { 'button_text_light' => false } }, {})['button_text_light']).to be(false)
      end
    end
  end
end
