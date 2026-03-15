# spec/unit/onetime/application/build_available_locales_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Application::MiddlewareStack, '.build_available_locales' do
  # The full set of 30 supported locales matching generated/locales/*.json
  let(:all_supported_locales) do
    %w[
      ar bg ca_ES cs da_DK de de_AT el_GR en eo es
      fr_CA fr_FR he hu it_IT ja ko mi_NZ nl pl
      pt_BR pt_PT ru sl_SI sv_SE tr uk vi zh
    ]
  end

  before do
    allow(OT).to receive(:supported_locales).and_return(supported_locales)
  end

  describe 'primary language code fallback entries' do
    let(:supported_locales) { all_supported_locales }

    it 'includes all 30 canonical locale entries' do
      result = described_class.build_available_locales
      all_supported_locales.each do |locale|
        expect(result).to have_key(locale),
          "Expected locale map to include canonical entry '#{locale}'"
      end
    end

    it 'adds primary code "it" for regional variant "it_IT"' do
      result = described_class.build_available_locales
      expect(result).to have_key('it')
    end

    it 'maps primary code "it" to the same name as "it_IT"' do
      result = described_class.build_available_locales
      expect(result['it']).to eq(result['it_IT'])
    end

    it 'adds primary code "fr" for regional variant "fr_CA" (first encountered)' do
      result = described_class.build_available_locales
      expect(result).to have_key('fr')
    end

    it 'adds primary code "pt" for regional variant "pt_BR"' do
      result = described_class.build_available_locales
      expect(result).to have_key('pt')
    end

    it 'adds primary code "da" for regional variant "da_DK"' do
      result = described_class.build_available_locales
      expect(result).to have_key('da')
    end

    it 'adds primary code "el" for regional variant "el_GR"' do
      result = described_class.build_available_locales
      expect(result).to have_key('el')
    end

    it 'adds primary code "ca" for regional variant "ca_ES"' do
      result = described_class.build_available_locales
      expect(result).to have_key('ca')
    end

    it 'adds primary code "sl" for regional variant "sl_SI"' do
      result = described_class.build_available_locales
      expect(result).to have_key('sl')
    end

    it 'adds primary code "sv" for regional variant "sv_SE"' do
      result = described_class.build_available_locales
      expect(result).to have_key('sv')
    end

    it 'adds primary code "mi" for regional variant "mi_NZ"' do
      result = described_class.build_available_locales
      expect(result).to have_key('mi')
    end

    it 'generates primary code entries for all regional variants' do
      result = described_class.build_available_locales

      regional_variants = all_supported_locales.select { |l| l.include?('_') }
      regional_variants.each do |variant|
        primary = variant.split('_').first
        expect(result).to have_key(primary),
          "Expected primary code '#{primary}' for regional variant '#{variant}'"
      end
    end
  end

  describe 'preserving existing primary code entries' do
    let(:supported_locales) { %w[de de_AT] }

    it 'does not overwrite existing primary code "de" with de_AT value' do
      result = described_class.build_available_locales
      expect(result['de']).to eq('Deutsch')
      expect(result['de_AT']).to eq('Deutsch (Österreich)')
    end
  end

  describe 'first-encountered regional variant wins for primary code' do
    context 'when fr_CA appears before fr_FR' do
      let(:supported_locales) { %w[fr_CA fr_FR] }

      it 'maps "fr" to fr_CA name (first encountered)' do
        result = described_class.build_available_locales
        expect(result['fr']).to eq(result['fr_CA'])
      end
    end

    context 'when pt_BR appears before pt_PT' do
      let(:supported_locales) { %w[pt_BR pt_PT] }

      it 'maps "pt" to pt_BR name (first encountered)' do
        result = described_class.build_available_locales
        expect(result['pt']).to eq(result['pt_BR'])
      end
    end
  end

  describe 'simple locale codes without regional variants' do
    let(:supported_locales) { %w[en es ja ko] }

    it 'includes them directly without adding duplicate primary entries' do
      result = described_class.build_available_locales
      expect(result.keys).to contain_exactly('en', 'es', 'ja', 'ko')
    end
  end

  describe 'total entry count with full locale list' do
    let(:supported_locales) { all_supported_locales }

    it 'has more entries than the supported_locales list due to primary code additions' do
      result = described_class.build_available_locales
      # 30 canonical + primary codes for regional variants that don't already exist
      # Regional variants: ca_ES, da_DK, el_GR, fr_CA, fr_FR, it_IT, mi_NZ,
      #                    pt_BR, pt_PT, sl_SI, sv_SE, de_AT
      # Primary codes already present: de (so de_AT doesn't add one)
      # New primary codes: ca, da, el, fr, it, mi, pt, sl, sv = 9
      expect(result.size).to eq(all_supported_locales.size + 9)
    end
  end

  describe 'locale name values' do
    let(:supported_locales) { %w[it_IT] }

    it 'uses the locale_names hash for known locales' do
      result = described_class.build_available_locales
      expect(result['it_IT']).to eq('Italiano')
    end

    it 'falls back to locale code string for unknown locales' do
      allow(OT).to receive(:supported_locales).and_return(%w[xx_YY])
      result = described_class.build_available_locales
      expect(result['xx_YY']).to eq('xx_YY')
    end
  end
end
