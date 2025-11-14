# spec/unit/apps/api/v2/logic/helpers/i18n_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'i18n'

RSpec.describe V2::Logic::I18nHelpers do
  # Create a test class that includes the helper module
  let(:test_logic_class) do
    Class.new do
      include V2::Logic::I18nHelpers

      attr_accessor :locale_value

      def locale
        @locale_value || 'en'
      end
    end
  end

  let(:logic) { test_logic_class.new }

  before(:each) do
    I18n.backend.reload!
    I18n.locale = :en
  end

  describe '#i18n' do
    it 'returns a hash with required keys' do
      result = logic.i18n

      expect(result).to be_a(Hash)
      expect(result).to have_key(:locale)
      expect(result).to have_key(:email)
      expect(result).to have_key(:web)
    end

    it 'sets locale to current locale' do
      logic.locale_value = 'en'
      result = logic.i18n

      expect(result[:locale]).to eq('en')
    end

    it 'includes email translations' do
      result = logic.i18n

      expect(result[:email]).to be_a(Hash)
    end

    it 'includes web translations' do
      result = logic.i18n

      expect(result[:web]).to be_a(Hash)
    end

    it 'caches results per locale' do
      logic.locale_value = 'en'

      # First call
      result1 = logic.i18n
      # Second call should return same object
      result2 = logic.i18n

      expect(result1.object_id).to eq(result2.object_id)
    end

    it 'maintains separate cache for different locales' do
      logic.locale_value = 'en'
      result_en = logic.i18n

      if OT.supported_locales.include?('fr')
        logic.locale_value = 'fr'
        result_fr = logic.i18n

        # Should have separate cache entries
        cache = logic.instance_variable_get(:@i18n_cache)
        expect(cache).to have_key('en')
        expect(cache).to have_key('fr')
      end
    end

    context 'when accessing translations' do
      it 'returns email section from I18n' do
        result = logic.i18n

        # Email section should exist
        expect(result[:email]).to be_a(Hash)
      end

      it 'returns web section from I18n' do
        result = logic.i18n

        # Web section should exist
        expect(result[:web]).to be_a(Hash)
      end

      it 'handles missing translations gracefully' do
        logic.locale_value = 'nonexistent'

        result = logic.i18n

        # Should return empty hashes as defaults
        expect(result[:email]).to eq({})
        expect(result[:web]).to eq({})
      end
    end
  end

  describe 'I18n integration' do
    it 'sets I18n.locale when accessing translations' do
      logic.locale_value = 'en'
      logic.i18n

      # The helper sets I18n.locale internally
      expect([:en, 'en']).to include(I18n.locale)
    end

    it 'uses I18n.t for loading translations' do
      logic.locale_value = OT.default_locale

      # This should work without errors
      expect { logic.i18n }.not_to raise_error
    end
  end

  describe 'usage in API context' do
    it 'provides access to email templates' do
      result = logic.i18n

      # API logic needs email translations
      expect(result[:email]).to be_a(Hash)
    end

    it 'provides access to web translations for error messages' do
      result = logic.i18n

      # API logic may need web translations for messages
      expect(result[:web]).to be_a(Hash)
    end
  end

  describe 'backward compatibility' do
    it 'provides same interface as legacy implementation' do
      result = logic.i18n

      # Legacy code expects these keys
      expect(result).to respond_to(:fetch)
      expect(result[:email]).to respond_to(:fetch)
      expect(result[:web]).to respond_to(:fetch)
    end

    it 'returns symbolized hash keys' do
      result = logic.i18n

      expect(result.keys).to all(be_a(Symbol))
      expect(result[:locale]).to be_a(String)
    end
  end

  describe 'locale switching behavior' do
    it 'respects locale changes between calls' do
      logic.locale_value = 'en'
      result_en = logic.i18n

      logic.locale_value = 'fr' if OT.supported_locales.include?('fr')
      result_fr = logic.i18n

      # Locales should be different
      expect(result_en[:locale]).to eq('en')
      if OT.supported_locales.include?('fr')
        expect(result_fr[:locale]).to eq('fr')
      end
    end
  end
end
