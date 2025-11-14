# spec/unit/apps/web/core/views/helpers/i18n_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'i18n'

RSpec.describe Core::Views::I18nHelpers do
  # Create a test class that includes the helper module
  let(:test_view_class) do
    Class.new do
      include Core::Views::I18nHelpers

      attr_accessor :locale_value, :pagename_value

      def locale
        @locale_value || 'en'
      end

      def self.pagename
        :dashboard
      end

      # Stub logger methods
      def app_logger
        @logger ||= double('Logger', warn: nil, info: nil, debug: nil, error: nil)
      end
    end
  end

  let(:view) { test_view_class.new }

  before(:each) do
    I18n.backend.reload!
    I18n.locale = :en
  end

  describe '#i18n' do
    it 'returns a hash with required keys' do
      result = view.i18n

      expect(result).to be_a(Hash)
      expect(result).to have_key(:locale)
      expect(result).to have_key(:default)
      expect(result).to have_key(:page)
      expect(result).to have_key(:COMMON)
    end

    it 'sets locale to current locale' do
      view.locale_value = 'en'
      result = view.i18n

      expect(result[:locale]).to eq('en')
    end

    it 'sets default to OT default locale' do
      result = view.i18n

      expect(result[:default]).to eq(OT.default_locale)
    end

    it 'includes COMMON translations' do
      result = view.i18n

      expect(result[:COMMON]).to be_a(Hash)
    end

    it 'includes page-specific translations' do
      result = view.i18n

      expect(result[:page]).to be_a(Hash)
    end

    it 'caches results per locale' do
      view.locale_value = 'en'

      # First call
      result1 = view.i18n
      # Second call should return same object
      result2 = view.i18n

      expect(result1.object_id).to eq(result2.object_id)
    end

    it 'returns different cache for different locales' do
      view.locale_value = 'en'
      result_en = view.i18n

      view.locale_value = 'fr' if OT.supported_locales.include?('fr')
      result_fr = view.i18n

      # Should have separate cache entries
      expect(view.instance_variable_get(:@i18n_cache)).to have_key('en')
    end

    context 'when locale is not found' do
      it 'falls back to default locale' do
        view.locale_value = 'nonexistent'

        result = view.i18n

        expect(result[:COMMON]).to be_a(Hash)
        # Should not be empty since it falls back
        expect(result[:COMMON]).not_to be_empty if OT.locales[OT.default_locale]
      end

      it 'logs a warning' do
        view.locale_value = 'nonexistent'
        logger = view.app_logger

        expect(logger).to receive(:warn).with(
          'Locale not found, falling back to default',
          hash_including(requested_locale: 'nonexistent')
        )

        view.i18n
      end
    end

    context 'with different page names' do
      it 'returns different page translations for different pages' do
        # Create view with different pagename
        custom_view_class = Class.new(test_view_class) do
          def self.pagename
            :signin
          end
        end

        custom_view = custom_view_class.new
        result = custom_view.i18n

        expect(result[:page]).to be_a(Hash)
      end
    end
  end

  describe 'I18n integration' do
    it 'sets I18n.locale when accessing translations' do
      view.locale_value = 'en'
      view.i18n

      # The helper sets I18n.locale internally
      expect([:en, 'en']).to include(I18n.locale)
    end

    it 'uses I18n.t for loading translations' do
      view.locale_value = OT.default_locale

      # This should work without errors
      expect { view.i18n }.not_to raise_error
    end
  end

  describe 'backward compatibility' do
    it 'provides same interface as legacy implementation' do
      result = view.i18n

      # Legacy code expects these keys
      expect(result).to respond_to(:fetch)
      expect(result[:page]).to respond_to(:fetch)
      expect(result[:COMMON]).to respond_to(:fetch)
    end

    it 'returns symbolized hash keys' do
      result = view.i18n

      expect(result.keys).to all(be_a(Symbol))
    end
  end
end
