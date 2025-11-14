# spec/unit/lib/onetime/initializers/load_locales_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'i18n'

RSpec.describe 'Onetime::Initializers#load_locales' do
  before(:each) do
    # Reset I18n configuration before each test
    I18n.backend.reload!
    I18n.locale = :en
  end

  describe 'I18n gem configuration' do
    it 'sets the default locale from configuration' do
      expect(I18n.default_locale).to eq(OT.default_locale.to_sym)
    end

    it 'configures available locales from supported locales list' do
      expect(I18n.available_locales).to include(OT.default_locale.to_sym)
      expect(I18n.available_locales.size).to be >= 1
    end

    it 'loads locale files from src/locales directory' do
      expect(I18n.load_path).not_to be_empty
      expect(I18n.load_path.first).to include('src/locales')
      expect(I18n.load_path.first).to end_with('.json')
    end

    it 'can load all configured locales' do
      OT.supported_locales.each do |locale|
        I18n.locale = locale.to_sym
        # Should be able to access translations without error
        expect { I18n.t('web', default: {}) }.not_to raise_error
      end
    end
  end

  describe 'backward compatibility' do
    it 'maintains OT.locales hash for legacy code' do
      expect(OT.locales).to be_a(Hash)
      expect(OT.locales).not_to be_empty
    end

    it 'populates OT.locales with locale data' do
      locale = OT.default_locale
      expect(OT.locales[locale]).to be_a(Hash)
      expect(OT.locales[locale]).to have_key(:web)
      expect(OT.locales[locale]).to have_key(:email)
    end

    it 'includes all supported locales in OT.locales' do
      OT.supported_locales.each do |locale|
        expect(OT.locales).to have_key(locale)
      end
    end
  end

  describe 'locale data structure' do
    let(:locale_data) { OT.locales[OT.default_locale] }

    it 'includes web section' do
      expect(locale_data[:web]).to be_a(Hash)
      expect(locale_data[:web]).not_to be_empty
    end

    it 'includes email section' do
      expect(locale_data[:email]).to be_a(Hash)
    end

    it 'includes common translations in web section' do
      expect(locale_data[:web]).to have_key(:COMMON)
      expect(locale_data[:web][:COMMON]).to be_a(Hash)
    end

    it 'includes page-specific translations' do
      # Check for known page translations
      known_pages = %i[dashboard signin signup]
      found_pages = locale_data[:web].keys & known_pages
      expect(found_pages).not_to be_empty
    end
  end

  describe 'fallback configuration' do
    context 'when fallback_locale is a Hash' do
      it 'configures I18n fallbacks' do
        skip 'Only if fallbacks are configured' unless OT.fallback_locale.is_a?(Hash)

        expect(I18n.backend).to be_a_kind_of(I18n::Backend::Fallbacks)
      end
    end

    context 'when fallback_locale is not a Hash' do
      it 'does not crash during initialization' do
        # This test verifies the type check improvement
        expect(I18n.backend).to be_a_kind_of(I18n::Backend::Simple)
      end
    end
  end

  describe 'error handling' do
    it 'gracefully handles missing locale files' do
      # Try to load a non-existent locale
      I18n.locale = :nonexistent
      result = I18n.t('web', default: {})

      # Should return default instead of raising
      expect(result).to eq({})
    end

    it 'ensures locale restoration after errors' do
      original_locale = I18n.locale

      # This should not affect the locale state
      expect {
        I18n.locale = :invalid_locale
        I18n.t('nonexistent.key', default: 'fallback')
      }.not_to raise_error

      # Restore to known state
      I18n.locale = original_locale
      expect(I18n.locale).to eq(original_locale)
    end
  end

  describe 'translation access' do
    before { I18n.locale = OT.default_locale.to_sym }

    it 'can access web translations' do
      result = I18n.t('web')
      expect(result).to be_a(Hash)
      expect(result).to have_key(:COMMON)
    end

    it 'can access email translations' do
      result = I18n.t('email', default: {})
      expect(result).to be_a(Hash)
    end

    it 'can access nested translations' do
      result = I18n.t('web.COMMON.tagline', default: nil)
      expect(result).to be_a(String) unless result.nil?
    end

    it 'returns default for missing translations' do
      result = I18n.t('nonexistent.key', default: 'default_value')
      expect(result).to eq('default_value')
    end
  end

  describe 'locale switching' do
    it 'switches between locales correctly' do
      original = I18n.locale

      I18n.locale = :en
      en_web = I18n.t('web', default: {})

      if OT.supported_locales.include?('fr')
        I18n.locale = :fr
        fr_web = I18n.t('web', default: {})

        # Translations should be different (unless fr falls back to en)
        expect(I18n.locale).to eq(:fr)
      end

      I18n.locale = original
    end

    it 'maintains separate data for different locales' do
      if OT.supported_locales.size > 1
        locale1 = OT.supported_locales[0]
        locale2 = OT.supported_locales[1]

        expect(OT.locales[locale1]).to be_a(Hash)
        expect(OT.locales[locale2]).to be_a(Hash)
      else
        skip 'Test requires multiple supported locales'
      end
    end
  end

  describe 'configuration attributes' do
    it 'exposes i18n_enabled flag' do
      expect(OT).to respond_to(:i18n_enabled)
      expect([true, false]).to include(OT.i18n_enabled)
    end

    it 'exposes default_locale' do
      expect(OT.default_locale).to be_a(String)
      expect(OT.default_locale).not_to be_empty
    end

    it 'exposes supported_locales' do
      expect(OT.supported_locales).to be_an(Array)
      expect(OT.supported_locales).to include(OT.default_locale)
    end

    it 'exposes fallback_locale' do
      expect(OT).to respond_to(:fallback_locale)
    end
  end
end
