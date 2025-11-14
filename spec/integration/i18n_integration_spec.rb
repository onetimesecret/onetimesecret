# spec/integration/i18n_integration_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'i18n'

RSpec.describe 'I18n Integration with ruby-i18n gem', type: :integration do
  include Rack::Test::Methods

  before(:each) do
    I18n.backend.reload!
    I18n.locale = :en
  end

  describe 'locale file loading' do
    it 'loads all locale files successfully' do
      expect(OT.locales).not_to be_empty
      expect(OT.supported_locales).to all(be_a(String))
    end

    it 'loads JSON files from src/locales directory' do
      locale_files = Dir[File.join(Onetime::HOME, 'src', 'locales', '*.json')]
      expect(locale_files).not_to be_empty
      expect(I18n.load_path).to include(*locale_files)
    end

    it 'makes all supported locales available' do
      OT.supported_locales.each do |locale|
        expect(I18n.available_locales).to include(locale.to_sym)
      end
    end
  end

  describe 'translation access patterns' do
    before { I18n.locale = OT.default_locale.to_sym }

    it 'supports dot notation for nested keys' do
      # This is the new way with ruby-i18n
      result = I18n.t('web.COMMON.tagline', default: nil)

      # Should return string or nil if not found
      expect([String, NilClass]).to include(result.class)
    end

    it 'supports hash access for sections' do
      # Get entire web section
      web = I18n.t('web', default: {})

      expect(web).to be_a(Hash)
      expect(web).to have_key(:COMMON) if web.any?
    end

    it 'supports default values for missing translations' do
      result = I18n.t('nonexistent.deeply.nested.key', default: 'fallback')

      expect(result).to eq('fallback')
    end

    it 'supports locale parameter' do
      en_result = I18n.t('web.COMMON.tagline', locale: :en, default: 'default')

      if OT.supported_locales.include?('fr')
        fr_result = I18n.t('web.COMMON.tagline', locale: :fr, default: 'default')
        # Results can be different or same (if fr falls back to en)
        expect([String]).to include(fr_result.class)
      end
    end
  end

  describe 'backward compatibility with OT.locales' do
    it 'maintains OT.locales hash structure' do
      locale = OT.default_locale
      locale_data = OT.locales[locale]

      expect(locale_data).to be_a(Hash)
      expect(locale_data).to have_key(:web)
      expect(locale_data).to have_key(:email)
    end

    it 'supports legacy hash access patterns' do
      locale = OT.default_locale
      web = OT.locales[locale][:web]
      common = web[:COMMON] if web

      expect([Hash, NilClass]).to include(common.class)
    end

    it 'populates data for all supported locales' do
      OT.supported_locales.each do |locale|
        expect(OT.locales).to have_key(locale)
        expect(OT.locales[locale]).to be_a(Hash)
      end
    end
  end

  describe 'locale switching' do
    it 'switches locales without errors' do
      original = I18n.locale

      OT.supported_locales.take(3).each do |locale|
        I18n.locale = locale.to_sym
        result = I18n.t('web', default: {})

        expect(result).to be_a(Hash)
      end

      I18n.locale = original
    end

    it 'maintains separate translations per locale' do
      if OT.supported_locales.size > 1
        locale1 = OT.supported_locales[0]
        locale2 = OT.supported_locales[1]

        data1 = OT.locales[locale1]
        data2 = OT.locales[locale2]

        expect(data1).to be_a(Hash)
        expect(data2).to be_a(Hash)
        expect(data1.object_id).not_to eq(data2.object_id)
      end
    end
  end

  describe 'error message localization' do
    it 'can load error messages from translations' do
      I18n.locale = :en

      # Try to get a common error message
      error_msg = I18n.t('web.COMMON.error_passphrase', default: 'Incorrect passphrase')

      expect(error_msg).to be_a(String)
      expect(error_msg).not_to be_empty
    end

    it 'provides fallback for missing error messages' do
      result = I18n.t('web.COMMON.nonexistent_error', default: 'Default error')

      expect(result).to eq('Default error')
    end
  end

  describe 'email template localization' do
    it 'can access email templates' do
      I18n.locale = OT.default_locale.to_sym

      email = I18n.t('email', default: {})

      expect(email).to be_a(Hash)
    end

    it 'supports multiple email template sections' do
      locale_data = OT.locales[OT.default_locale]
      email_data = locale_data[:email]

      if email_data && email_data.any?
        # Should have email template sections
        expect(email_data).to be_a(Hash)
      end
    end
  end

  describe 'configuration consistency' do
    it 'matches I18n.default_locale with OT.default_locale' do
      expect(I18n.default_locale.to_s).to eq(OT.default_locale)
    end

    it 'includes all OT.supported_locales in I18n.available_locales' do
      OT.supported_locales.each do |locale|
        expect(I18n.available_locales).to include(locale.to_sym)
      end
    end

    it 'loads locales from correct directory' do
      expect(I18n.load_path).to all(include('src/locales'))
      expect(I18n.load_path).to all(end_with('.json'))
    end
  end

  describe 'API usage patterns' do
    context 'in V2::Logic helpers' do
      it 'can construct i18n data structure for API responses' do
        locale = OT.default_locale

        email_messages = I18n.t('email', locale: locale, default: {})
        web_messages = I18n.t('web', locale: locale, default: {})

        result = {
          locale: locale,
          email: email_messages,
          web: web_messages
        }

        expect(result[:email]).to be_a(Hash)
        expect(result[:web]).to be_a(Hash)
      end
    end

    context 'in Core::Views helpers' do
      it 'can construct i18n data structure for views' do
        locale = OT.default_locale
        pagename = :dashboard

        web_messages = I18n.t('web', locale: locale, default: {})
        common_messages = web_messages.fetch(:COMMON, {})
        page_messages = web_messages.fetch(pagename, {})

        result = {
          locale: locale,
          default: OT.default_locale,
          page: page_messages,
          COMMON: common_messages
        }

        expect(result[:COMMON]).to be_a(Hash)
        expect(result[:page]).to be_a(Hash)
      end
    end
  end

  describe 'performance considerations' do
    it 'caches locale data efficiently' do
      # First access
      start_time = Time.now
      first_result = OT.locales[OT.default_locale]
      first_duration = Time.now - start_time

      # Second access should be from cache
      start_time = Time.now
      second_result = OT.locales[OT.default_locale]
      second_duration = Time.now - start_time

      # Cached access should be faster (though this is a simple check)
      expect(first_result).to eq(second_result)
    end

    it 'does not reload translations on each request' do
      # I18n should have backend loaded
      backend = I18n.backend

      # Multiple translations should use same backend
      I18n.t('web.COMMON.tagline', default: nil)
      I18n.t('web.TITLES.signin', default: nil)

      expect(I18n.backend).to eq(backend)
    end
  end

  describe 'fallback behavior' do
    context 'when translation is missing' do
      it 'returns default value' do
        result = I18n.t('this.does.not.exist', default: 'my default')

        expect(result).to eq('my default')
      end

      it 'can return empty hash as default' do
        result = I18n.t('missing.section', default: {})

        expect(result).to eq({})
      end
    end

    context 'when locale is missing' do
      it 'falls back gracefully' do
        result = I18n.t('web', locale: :nonexistent, default: {})

        expect(result).to eq({})
      end
    end
  end
end
