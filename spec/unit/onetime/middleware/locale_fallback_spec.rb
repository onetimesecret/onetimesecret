# spec/unit/onetime/middleware/locale_fallback_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'middleware/locale_fallback'

RSpec.describe Middleware::LocaleFallback do
  let(:inner_app) { ->(env) { [200, { 'Content-Type' => 'text/plain' }, [env['otto.locale']]] } }

  let(:available_locales) do
    {
      'en' => 'English',
      'fr' => 'Français (France)',
      'fr_FR' => 'Français (France)',
      'fr_CA' => 'Français (Canada)',
      'pt_BR' => 'Português (Brasil)',
      'pt_PT' => 'Português (Portugal)',
      'de' => 'Deutsch',
      'de_AT' => 'Deutsch (Österreich)',
      'es' => 'Español',
      'it_IT' => 'Italiano',
      'it' => 'Italiano',
    }
  end

  let(:fallback_chains) do
    {
      'fr' => %w[fr_FR fr_CA en],
      'fr-CA' => %w[fr_CA fr_FR en],
      'pt' => %w[pt_BR pt_PT en],
      'pt-BR' => %w[pt_BR pt_PT en],
      'pt-PT' => %w[pt_PT pt_BR en],
      'de-AT' => %w[de_AT de en],
      'default' => %w[en],
    }
  end

  let(:middleware) do
    described_class.new(inner_app,
      fallback_chains: fallback_chains,
      available_locales: available_locales,
      default_locale: 'en')
  end

  def make_env(accept_language: nil, otto_locale: 'en', query_string: '', session: {})
    env = {
      'otto.locale' => otto_locale,
      'QUERY_STRING' => query_string,
      'rack.session' => session,
    }
    env['HTTP_ACCEPT_LANGUAGE'] = accept_language if accept_language
    env
  end

  describe 'fallback chain resolution' do
    it 'resolves fr-CA to fr_CA when available' do
      env = make_env(accept_language: 'fr-CA')
      _status, _headers, body = middleware.call(env)
      expect(body.first).to eq('fr_CA')
    end

    it 'resolves pt-PT to pt_PT via fallback chain' do
      env = make_env(accept_language: 'pt-PT,pt;q=0.9,en;q=0.5')
      _status, _headers, body = middleware.call(env)
      expect(body.first).to eq('pt_PT')
    end

    it 'resolves de-AT to de_AT when available' do
      env = make_env(accept_language: 'de-AT,de;q=0.8')
      _status, _headers, body = middleware.call(env)
      expect(body.first).to eq('de_AT')
    end

    it 'falls through chain when first entry is unavailable' do
      # Remove fr_CA from available locales
      limited_locales = available_locales.reject { |k, _| k == 'fr_CA' }
      mw = described_class.new(inner_app,
        fallback_chains: fallback_chains,
        available_locales: limited_locales,
        default_locale: 'en')

      env = make_env(accept_language: 'fr-CA')
      _status, _headers, body = mw.call(env)
      expect(body.first).to eq('fr_FR')
    end

    it 'falls back to en when no chain entries are available' do
      empty_locales = { 'en' => 'English' }
      mw = described_class.new(inner_app,
        fallback_chains: fallback_chains,
        available_locales: empty_locales,
        default_locale: 'en')

      env = make_env(accept_language: 'fr-CA')
      _status, _headers, body = mw.call(env)
      expect(body.first).to eq('en')
    end

    it 'resolves primary code through fallback chain' do
      env = make_env(accept_language: 'fr')
      _status, _headers, body = middleware.call(env)
      expect(body.first).to eq('fr_FR')
    end
  end

  describe 'explicit locale bypass' do
    it 'does not override when locale is set by URL param' do
      env = make_env(
        accept_language: 'fr-CA',
        otto_locale: 'es',
        query_string: 'locale=es'
      )
      _status, _headers, body = middleware.call(env)
      expect(body.first).to eq('es')
    end

    it 'does not override when locale is set in session' do
      env = make_env(
        accept_language: 'fr-CA',
        otto_locale: 'de',
        session: { 'locale' => 'de' }
      )
      _status, _headers, body = middleware.call(env)
      expect(body.first).to eq('de')
    end
  end

  describe 'no Accept-Language header' do
    it 'leaves otto.locale unchanged when header is absent' do
      env = make_env(otto_locale: 'en')
      _status, _headers, body = middleware.call(env)
      expect(body.first).to eq('en')
    end
  end

  describe 'no matching fallback chain' do
    it 'leaves otto.locale unchanged for unconfigured locales' do
      env = make_env(accept_language: 'ja', otto_locale: 'en')
      _status, _headers, body = middleware.call(env)
      expect(body.first).to eq('en')
    end
  end

  describe 'q-value ordering' do
    it 'respects q-value ordering across multiple tags' do
      # User prefers pt-PT most, but also accepts fr-CA
      env = make_env(accept_language: 'fr-CA;q=0.5,pt-PT;q=0.9')
      _status, _headers, body = middleware.call(env)
      expect(body.first).to eq('pt_PT')
    end
  end

  describe 'empty or nil fallback chains' do
    it 'handles nil fallback_chains gracefully' do
      mw = described_class.new(inner_app,
        fallback_chains: nil,
        available_locales: available_locales,
        default_locale: 'en')

      env = make_env(accept_language: 'fr-CA', otto_locale: 'en')
      _status, _headers, body = mw.call(env)
      expect(body.first).to eq('en')
    end

    it 'handles empty fallback_chains gracefully' do
      mw = described_class.new(inner_app,
        fallback_chains: {},
        available_locales: available_locales,
        default_locale: 'en')

      env = make_env(accept_language: 'fr-CA', otto_locale: 'en')
      _status, _headers, body = mw.call(env)
      expect(body.first).to eq('en')
    end
  end

  describe 'BCP 47 / underscore normalization' do
    it 'handles underscore-keyed chains in config' do
      chains_with_underscores = {
        'fr_CA' => %w[fr_CA fr_FR en],
      }
      mw = described_class.new(inner_app,
        fallback_chains: chains_with_underscores,
        available_locales: available_locales,
        default_locale: 'en')

      env = make_env(accept_language: 'fr-CA')
      _status, _headers, body = mw.call(env)
      expect(body.first).to eq('fr_CA')
    end
  end
end
