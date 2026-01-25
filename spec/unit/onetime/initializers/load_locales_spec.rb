# spec/unit/onetime/initializers/load_locales_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/initializers/load_locales'

RSpec.describe Onetime::Initializers::LoadLocales do
  let(:instance) { described_class.new }
  let(:context) { double('context') }
  let(:locales_path) { File.join(Onetime::HOME, 'generated', 'locales') }

  before do
    # Reset runtime state before each test
    Onetime::Runtime.reset!
    allow(OT).to receive(:conf).and_return(config)
    # Stub logging to keep test output clean
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(OT).to receive(:info)
  end

  describe '#execute' do
    context 'when i18n is disabled' do
      let(:config) { { 'internationalization' => { 'enabled' => false } } }

      it 'sets default english-only runtime state' do
        instance.execute(context)
        state = Onetime::Runtime.internationalization

        expect(state.enabled).to be false
        expect(state.supported_locales).to eq(['en'])
        expect(state.default_locale).to eq('en')
        expect(state.fallback_locale).to be_nil
      end
    end

    context 'with legacy configuration' do
      let(:config) { { 'locales' => ['en', 'de'], 'internationalization' => { 'enabled' => true } } }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(include('en.json')).and_return(true)
        allow(File).to receive(:exist?).with(include('de.json')).and_return(true)
        allow(File).to receive(:read).and_return('{}')
      end

      it 'uses the top-level locales list' do
        instance.execute(context)
        state = Onetime::Runtime.internationalization
        expect(state.supported_locales).to eq(['en', 'de'])
      end
    end

    context 'when i18n is enabled' do
      let(:config) do
        {
          'internationalization' => {
            'enabled' => true,
            'locales' => ['en', 'es'],
            'default_locale' => 'en'
          }
        }
      end

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(include('en.json')).and_return(true)
        allow(File).to receive(:exist?).with(include('es.json')).and_return(true)
        allow(File).to receive(:read).with(include('en.json')).and_return('{"web":{"test":"English"}}')
        allow(File).to receive(:read).with(include('es.json')).and_return('{"web":{"test":"Spanish"}}')
      end

      it 'loads locales from generated/locales files' do
        instance.execute(context)
        state = Onetime::Runtime.internationalization

        expect(state.enabled).to be true
        expect(state.supported_locales).to eq(['en', 'es'])
        expect(state.locales['en']).to eq({ 'web' => { 'test' => 'English' } })
        expect(state.locales['es']).to eq({ 'web' => { 'test' => 'Spanish' } })
      end

      it 'logs loading of each locale' do
        instance.execute(context)

        expect(OT).to have_received(:ld).with(/Loading en:/)
        expect(OT).to have_received(:ld).with(/Loading es:/)
      end
    end

    context 'when translations are missing in a non-default locale' do
      let(:config) do
        {
          'internationalization' => {
            'enabled' => true,
            'locales' => ['en', 'fr'],
            'default_locale' => 'en'
          }
        }
      end

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(include('en.json')).and_return(true)
        allow(File).to receive(:exist?).with(include('fr.json')).and_return(true)
        # Default locale (en) has all keys
        allow(File).to receive(:read).with(include('en.json')).and_return('{"common":{"save":"Save","cancel":"Cancel"}}')
        # French (fr) is missing "cancel"
        allow(File).to receive(:read).with(include('fr.json')).and_return('{"common":{"save":"Enregistrer"}}')
      end

      it 'applies default locale fallback via deep_merge' do
        instance.execute(context)
        state = Onetime::Runtime.internationalization

        fr_defs = state.locales['fr']
        expect(fr_defs['common']['save']).to eq('Enregistrer')
        expect(fr_defs['common']['cancel']).to eq('Cancel') # Fallback to English
      end
    end

    context 'validation and error handling' do
      let(:config) do
        {
          'internationalization' => {
            'enabled' => true,
            'locales' => ['en'],
            'default_locale' => 'fr' # Invalid: fr is not in locales list
          }
        }
      end

      it 'disables i18n if default_locale is not in supported list' do
        instance.execute(context)
        state = Onetime::Runtime.internationalization

        expect(state.enabled).to be false
        expect(state.default_locale).to eq('en') # Reverts to default
        expect(OT).to have_received(:le).with(/Default locale fr not in locales_list/)
      end

      it 'handles JSON parser errors gracefully' do
        config_valid = {
          'internationalization' => {
            'enabled' => true,
            'locales' => ['en'],
            'default_locale' => 'en'
          }
        }
        allow(OT).to receive(:conf).and_return(config_valid)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(include('en.json')).and_return(true)
        allow(File).to receive(:read).and_return('INVALID JSON {')
        # Mocking JSON::ParserError ensures the implementation's rescue block is triggered
        allow(Familia::JsonSerializer).to receive(:parse).and_raise(JSON::ParserError.new('Mock error'))

        instance.execute(context)
        state = Onetime::Runtime.internationalization

        # When loading fails, locale is not added to the hash
        expect(state.locales).to eq({})
        expect(OT).to have_received(:le).with(/JSON parse error/)
      end

      it 'handles missing locale files' do
        config_valid = {
          'internationalization' => {
            'enabled' => true,
            'locales' => ['de'],
            'default_locale' => 'de'
          }
        }
        allow(OT).to receive(:conf).and_return(config_valid)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(include('de.json')).and_return(false)

        instance.execute(context)
        state = Onetime::Runtime.internationalization

        # When loading fails, locale is not added to the hash
        expect(state.locales).to eq({})
        expect(OT).to have_received(:le).with(/Missing locale file:/)
      end
    end
  end

  describe 'LOCALES_ROOT' do
    let(:config) { { 'internationalization' => { 'enabled' => false } } }

    it 'points to generated/locales directory' do
      expect(described_class::LOCALES_ROOT).to eq(File.join(Onetime::HOME, 'generated', 'locales'))
    end
  end
end
