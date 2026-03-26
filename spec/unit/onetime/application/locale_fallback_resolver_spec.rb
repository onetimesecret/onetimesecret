# spec/unit/onetime/application/locale_fallback_resolver_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'middleware/locale_fallback'

RSpec.describe Middleware::LocaleFallback do
  # Build the available_locales hash the same way MiddlewareStack does:
  # a Hash mapping locale codes to display names.
  let(:all_available_locales) do
    {
      'ar' => 'العربية',
      'bg' => 'Български',
      'ca_ES' => 'Català',
      'cs' => 'Čeština',
      'da_DK' => 'Dansk',
      'de' => 'Deutsch',
      'de_AT' => 'Deutsch (Österreich)',
      'el_GR' => 'Ελληνικά',
      'en' => 'English',
      'eo' => 'Esperanto',
      'es' => 'Español',
      'fr_CA' => 'Français (Canada)',
      'fr_FR' => 'Français (France)',
      'he' => 'עברית',
      'hu' => 'Magyar',
      'it_IT' => 'Italiano',
      'ja' => '日本語',
      'ko' => '한국어',
      'mi_NZ' => 'Te Reo Māori',
      'nl' => 'Nederlands',
      'pl' => 'Polski',
      'pt_BR' => 'Português (Brasil)',
      'pt_PT' => 'Português (Portugal)',
      'ru' => 'Русский',
      'sl_SI' => 'Slovenščina',
      'sv_SE' => 'Svenska',
      'tr' => 'Türkçe',
      'uk' => 'Українська',
      'vi' => 'Tiếng Việt',
      'zh' => '中文',
    }
  end

  # The full fallback_locale config from config.defaults.yaml
  let(:full_fallback_config) do
    {
      'ca' => %w[ca_ES en],
      'ca-ES' => %w[ca_ES en],
      'da' => %w[da_DK en],
      'da-DK' => %w[da_DK en],
      'de' => %w[de de_AT en],
      'de-AT' => %w[de_AT de en],
      'el' => %w[el_GR en],
      'el-GR' => %w[el_GR en],
      'fr' => %w[fr_FR fr_CA en],
      'fr-CA' => %w[fr_CA fr_FR en],
      'it' => %w[it_IT en],
      'mi' => %w[mi_NZ en],
      'mi-NZ' => %w[mi_NZ en],
      'pt' => %w[pt_BR pt_PT en],
      'pt-BR' => %w[pt_BR pt_PT en],
      'pt-PT' => %w[pt_PT pt_BR en],
      'sl' => %w[sl_SI en],
      'sl-SI' => %w[sl_SI en],
      'sv' => %w[sv_SE en],
      'sv-SE' => %w[sv_SE en],
      'default' => %w[en],
    }
  end

  let(:available_locales) { all_available_locales }
  let(:fallback_config) { full_fallback_config }
  let(:default_locale) { 'en' }

  # Inner app that captures the env for inspection
  let(:captured_env) { {} }
  let(:inner_app) do
    lambda { |env|
      captured_env.merge!(env)
      [200, {}, ['OK']]
    }
  end

  let(:middleware) do
    described_class.new(
      inner_app,
      fallback_chains: fallback_config,
      available_locales: available_locales,
      default_locale: default_locale
    )
  end

  # Simulate a request with a given Accept-Language header.
  # Returns the locale that was set in env['otto.locale'] by the middleware.
  def resolved_locale(accept_language, query_string: '', session: {})
    env = Rack::MockRequest.env_for(
      '/',
      'HTTP_ACCEPT_LANGUAGE' => accept_language,
      'QUERY_STRING' => query_string
    )
    env['rack.session'] = session
    # Pre-set otto.locale as Otto::Locale::Middleware would
    env['otto.locale'] = default_locale
    middleware.call(env)
    captured_env['otto.locale']
  end

  describe 'basic fallback chain resolution' do
    it 'resolves fr-CA to fr_CA (first in chain, available)' do
      expect(resolved_locale('fr-CA')).to eq('fr_CA')
    end

    it 'resolves fr to fr_FR (first in chain for bare fr)' do
      expect(resolved_locale('fr')).to eq('fr_FR')
    end

    it 'resolves pt-PT to pt_PT when available' do
      expect(resolved_locale('pt-PT')).to eq('pt_PT')
    end

    it 'resolves pt to pt_BR (first in chain for bare pt)' do
      expect(resolved_locale('pt')).to eq('pt_BR')
    end

    it 'resolves ca to ca_ES' do
      expect(resolved_locale('ca')).to eq('ca_ES')
    end

    it 'resolves da to da_DK' do
      expect(resolved_locale('da')).to eq('da_DK')
    end

    it 'resolves el to el_GR' do
      expect(resolved_locale('el')).to eq('el_GR')
    end

    it 'resolves sv to sv_SE' do
      expect(resolved_locale('sv')).to eq('sv_SE')
    end

    it 'resolves mi to mi_NZ' do
      expect(resolved_locale('mi')).to eq('mi_NZ')
    end

    it 'resolves sl to sl_SI' do
      expect(resolved_locale('sl')).to eq('sl_SI')
    end

    it 'resolves it to it_IT' do
      expect(resolved_locale('it')).to eq('it_IT')
    end
  end

  describe 'fallback when preferred locale is unavailable' do
    context 'when fr_CA is removed from available locales' do
      let(:available_locales) { all_available_locales.except('fr_CA') }

      it 'falls through fr-CA chain to fr_FR' do
        expect(resolved_locale('fr-CA')).to eq('fr_FR')
      end
    end

    context 'when fr_FR is removed from available locales' do
      let(:available_locales) { all_available_locales.except('fr_FR') }

      it 'falls through fr chain to fr_CA' do
        expect(resolved_locale('fr')).to eq('fr_CA')
      end
    end

    context 'when both pt_BR and pt_PT are unavailable' do
      let(:available_locales) { all_available_locales.except('pt_BR', 'pt_PT') }

      it 'falls through pt chain to en' do
        expect(resolved_locale('pt')).to eq('en')
      end
    end

    context 'when all chain locales except en are unavailable' do
      let(:available_locales) { { 'en' => 'English', 'de' => 'Deutsch' } }

      it 'falls through fr chain to en' do
        expect(resolved_locale('fr')).to eq('en')
      end
    end
  end

  describe 'edge cases' do
    context 'unknown locale with no fallback chain' do
      it 'does not change the otto.locale (stays at default)' do
        # xx has no chain, so resolve_from_header returns nil
        # and otto.locale stays at whatever Otto set (the default)
        expect(resolved_locale('xx')).to eq(default_locale)
      end

      it 'does not change otto.locale for completely unknown zz-ZZ' do
        expect(resolved_locale('zz-ZZ')).to eq(default_locale)
      end
    end

    it 'resolves de-AT to de_AT (regional variant preferred)' do
      expect(resolved_locale('de-AT')).to eq('de_AT')
    end

    it 'resolves de to de (exact match preferred, not de_AT)' do
      expect(resolved_locale('de')).to eq('de')
    end

    context 'nil or missing Accept-Language header' do
      it 'does not change otto.locale when header is nil' do
        env = Rack::MockRequest.env_for('/')
        env['rack.session'] = {}
        env['otto.locale'] = 'en'
        # No HTTP_ACCEPT_LANGUAGE set
        middleware.call(env)
        expect(env['otto.locale']).to eq('en')
      end
    end

    context 'case insensitivity' do
      it 'handles FR-CA the same as fr-CA' do
        expect(resolved_locale('FR-CA')).to eq('fr_CA')
      end

      it 'handles Fr-Ca the same as fr-CA' do
        expect(resolved_locale('Fr-Ca')).to eq('fr_CA')
      end

      it 'handles PT the same as pt' do
        expect(resolved_locale('PT')).to eq('pt_BR')
      end

      it 'handles DE-AT the same as de-AT' do
        expect(resolved_locale('DE-AT')).to eq('de_AT')
      end
    end

    context 'when en is requested directly' do
      # en has no explicit chain in the config (only the 'default' key),
      # but the middleware should not break on it
      it 'does not change otto.locale away from en' do
        locale = resolved_locale('en')
        # en might stay as default or be explicitly resolved — either way valid
        expect(locale).to eq('en')
      end
    end
  end

  describe 'explicit locale bypasses fallback' do
    context 'when locale is set via URL parameter' do
      it 'does not override the URL param locale' do
        locale = resolved_locale('fr-CA', query_string: 'locale=de')
        # The middleware should NOT intervene; otto.locale stays at
        # whatever Otto set (the default in our test setup)
        expect(locale).to eq(default_locale)
      end
    end

    context 'when locale is set via session' do
      it 'does not override the session locale' do
        locale = resolved_locale('fr-CA', session: { 'locale' => 'de' })
        expect(locale).to eq(default_locale)
      end
    end

    context 'when no explicit locale and no session' do
      it 'applies fallback chain from Accept-Language' do
        locale = resolved_locale('fr-CA', query_string: '', session: {})
        expect(locale).to eq('fr_CA')
      end
    end
  end

  describe 'priority and precedence' do
    context 'fallback chain order is respected (first available wins)' do
      it 'resolves pt-BR to pt_BR (first in pt-BR chain)' do
        expect(resolved_locale('pt-BR')).to eq('pt_BR')
      end

      it 'resolves pt-PT to pt_PT (first in pt-PT chain), not pt_BR' do
        expect(resolved_locale('pt-PT')).to eq('pt_PT')
      end
    end

    context 'chain order matters when first choice is unavailable' do
      # pt-PT chain: [pt_PT, pt_BR, en]
      let(:available_locales) { all_available_locales.except('pt_PT') }

      it 'resolves pt-PT to pt_BR when pt_PT is unavailable' do
        expect(resolved_locale('pt-PT')).to eq('pt_BR')
      end
    end
  end

  describe 'hyphen-to-underscore normalization' do
    it 'normalizes browser-style fr-CA to file-style fr_CA' do
      expect(resolved_locale('fr-CA')).to eq('fr_CA')
    end

    it 'normalizes pt-BR to pt_BR' do
      expect(resolved_locale('pt-BR')).to eq('pt_BR')
    end

    it 'normalizes de-AT to de_AT' do
      expect(resolved_locale('de-AT')).to eq('de_AT')
    end
  end

  describe 'Accept-Language with q-values' do
    it 'respects q-value priority (prefers higher q)' do
      # fr-CA;q=0.8, de;q=0.9 — de should be preferred
      locale = resolved_locale('fr-CA;q=0.8, de;q=0.9')
      expect(locale).to eq('de')
    end

    it 'resolves first matching tag from sorted q-values' do
      # pt-BR;q=0.5, fr-CA;q=0.9 — fr-CA should win
      locale = resolved_locale('pt-BR;q=0.5, fr-CA;q=0.9')
      expect(locale).to eq('fr_CA')
    end

    it 'handles default q=1.0 for tags without explicit q' do
      # fr-CA (implicit q=1.0) should win over de;q=0.5
      locale = resolved_locale('fr-CA, de;q=0.5')
      expect(locale).to eq('fr_CA')
    end
  end

  describe 'minimal supported locales' do
    context 'when only en is available' do
      let(:available_locales) { { 'en' => 'English' } }

      it 'resolves fr to en (only available locale in chain)' do
        expect(resolved_locale('fr')).to eq('en')
      end

      it 'resolves de to en via chain' do
        expect(resolved_locale('de')).to eq('en')
      end
    end

    context 'when only fr_FR and en are available' do
      let(:available_locales) { { 'fr_FR' => 'Français (France)', 'en' => 'English' } }

      it 'resolves fr-CA to fr_FR (fr_CA unavailable, fr_FR is next in chain)' do
        expect(resolved_locale('fr-CA')).to eq('fr_FR')
      end

      it 'resolves fr to fr_FR' do
        expect(resolved_locale('fr')).to eq('fr_FR')
      end
    end
  end

  describe 'integration with MiddlewareStack.build_available_locales' do
    # Verify that the available_locales hash produced by build_available_locales
    # is compatible with the LocaleFallback middleware's expectations.

    before do
      allow(OT).to receive(:supported_locales).and_return(
        all_available_locales.keys.select { |k| !k.include?('_') || all_available_locales.key?(k) }
      )
    end

    it 'build_available_locales returns a Hash (not an Array)' do
      result = Onetime::Application::MiddlewareStack.build_available_locales
      expect(result).to be_a(Hash)
    end

    it 'build_available_locales hash has string keys usable by LocaleFallback' do
      result = Onetime::Application::MiddlewareStack.build_available_locales
      expect(result.keys).to all(be_a(String))
    end
  end

  describe 'chain lookup normalization' do
    # The middleware normalizes config keys so both hyphen and underscore
    # forms can be looked up. This tests the internal build_chain_lookup.

    let(:fallback_config) do
      { 'fr-CA' => %w[fr_CA fr_FR en] }
    end

    it 'resolves fr-CA through the hyphen-keyed chain' do
      expect(resolved_locale('fr-CA')).to eq('fr_CA')
    end

    # The middleware also stores underscore variant of hyphen keys
    it 'resolves fr_CA input through the same chain' do
      expect(resolved_locale('fr_CA')).to eq('fr_CA')
    end
  end

  describe 'primary code fallback for unmatched regional tags' do
    # When a specific regional tag like mi-NZ has no explicit chain,
    # but the primary code "mi" does, the middleware should fall back
    # to the primary code's chain.
    let(:fallback_config) do
      {
        'mi' => %w[mi_NZ en],
        'default' => %w[en],
      }
    end

    it 'resolves mi-NZ via primary code mi chain when no mi-NZ chain exists' do
      expect(resolved_locale('mi-NZ')).to eq('mi_NZ')
    end
  end
end
