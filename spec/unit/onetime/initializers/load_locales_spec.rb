# frozen_string_literal: true

require 'spec_helper'
require 'onetime/initializers/load_locales'

RSpec.describe Onetime::Initializers::LoadLocales do
  let(:instance) { described_class.new }
  let(:context) { double('context') }
  let(:locales_path) { File.join(Onetime::HOME, 'src', 'locales') }

  before do
    # Reset runtime state before each test
    Onetime::Runtime.reset!
    allow(OT).to receive(:conf).and_return(config)
    # Stub logging to keep test output clean
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
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
        allow(Dir).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return('{}')
      end

      it 'uses the top-level locales list' do
        instance.execute(context)
        state = Onetime::Runtime.internationalization
        expect(state.supported_locales).to eq(['en', 'de'])
      end
    end

    context 'when i18n is enabled with monolithic files' do
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
        allow(Dir).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with(include('en.json')).and_return(true)
        allow(File).to receive(:exist?).with(include('es.json')).and_return(true)
        allow(File).to receive(:read).with(include('en.json')).and_return('{"web":{"test":"English"}}')
        allow(File).to receive(:read).with(include('es.json')).and_return('{"web":{"test":"Spanish"}}')
      end

      it 'loads locales from monolithic files' do
        instance.execute(context)
        state = Onetime::Runtime.internationalization

        expect(state.enabled).to be true
        expect(state.supported_locales).to eq(['en', 'es'])
        expect(state.locales['en']).to eq({ web: { test: 'English' } })
        expect(state.locales['es']).to eq({ 'web' => { 'test' => 'Spanish' } })
      end
    end

    context 'when i18n is enabled with split directory structure' do
      let(:config) do
        {
          'internationalization' => {
            'enabled' => true,
            'locales' => ['en'],
            'default_locale' => 'en'
          }
        }
      end
      let(:en_dir) { File.join(locales_path, 'en') }

      before do
        allow(Dir).to receive(:exist?).with(include('locales/en')).and_return(true)
        allow(Dir).to receive(:glob).with(include('locales/en/*.json')).and_return(
          ['/mock/web.json', '/mock/api.json']
        )
        allow(File).to receive(:read).with('/mock/web.json').and_return('{"web":{"key1":"val1"}}')
        allow(File).to receive(:read).with('/mock/api.json').and_return('{"web":{"key2":"val2"},"api":{"key3":"val3"}}')
        # Mock caching logic
        allow(File).to receive(:mtime).and_return(Time.now)
        allow(File).to receive(:exist?).with(include('tmp/cache/locales')).and_return(false)
        allow(File).to receive(:write).and_return(true)
        allow(FileUtils).to receive(:mkdir_p).and_return(true)
      end

      it 'merges multiple files for a single locale correctly' do
        instance.execute(context)
        state = Onetime::Runtime.internationalization

        expect(state.locales['en'][:web]).to eq({ key1: 'val1', key2: 'val2' })
        expect(state.locales['en'][:api]).to eq({ key3: 'val3' })
      end

      it 'loads from cache if available' do
        allow(File).to receive(:exist?).with(include('tmp/cache/locales')).and_return(true)
        allow(File).to receive(:read).with(include('tmp/cache/locales')).and_return('{"web":{"cached":"value"}}')

        instance.execute(context)
        state = Onetime::Runtime.internationalization
        expect(state.locales['en']).to eq({ web: { cached: 'value' } })
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
        allow(Dir).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).and_return(true)
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
        allow(Dir).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return('INVALID JSON {')
        # Mocking JSON::ParserError ensures the implementation's rescue block is triggered
        allow(Familia::JsonSerializer).to receive(:parse).and_raise(JSON::ParserError.new('Mock error'))

        instance.execute(context)
        state = Onetime::Runtime.internationalization

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
        allow(Dir).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).and_return(false)

        instance.execute(context)
        state = Onetime::Runtime.internationalization

        expect(state.locales).to eq({})
        expect(OT).to have_received(:le).with(/Missing locale: de/)
      end
    end
  end
end
