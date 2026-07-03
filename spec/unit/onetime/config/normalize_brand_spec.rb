# spec/unit/onetime/config/normalize_brand_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Config do
  describe '.normalize_brand' do
    # Render only matters as the "fallback" layer; these specs exercise the
    # Ruby normalization that is now the authority for the brand block.
    def normalized(conf, env)
      # Strip any ambient BRAND_* and legacy brand env vars — SITE_NAME /
      # LOGO_URL / LOGO_ALT feed LEGACY_BRAND_FALLBACKS (#3612) — sourced
      # from .env, so each case is isolated.
      base = ENV.to_h.reject do |k, _|
        k.start_with?('BRAND_') || %w[SITE_NAME LOGO_URL LOGO_ALT].include?(k)
      end
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

      it 'strips surrounding whitespace before the explicit-false comparison' do
        # ' false ' must still disable it — the comparison strips first, matching
        # every other field. Without stripping this silently returned true.
        expect(normalized({ 'brand' => {} }, 'BRAND_BUTTON_TEXT_LIGHT' => '  false  ')['button_text_light']).to be(false)
      end

      it 'is nil for a whitespace-only env value' do
        expect(normalized({ 'brand' => {} }, 'BRAND_BUTTON_TEXT_LIGHT' => '   ')['button_text_light']).to be_nil
      end

      it 'is true for any other set value' do
        expect(normalized({ 'brand' => {} }, 'BRAND_BUTTON_TEXT_LIGHT' => 'true')['button_text_light']).to be(true)
        expect(normalized({ 'brand' => {} }, 'BRAND_BUTTON_TEXT_LIGHT' => 'light')['button_text_light']).to be(true)
      end

      it 'coerces a YAML-parsed boolean false when the env var is unset' do
        expect(normalized({ 'brand' => { 'button_text_light' => false } }, {})['button_text_light']).to be(false)
      end
    end

    context 'legacy brand fallbacks (#3612)' do
      # Config carrying only the deprecated header.branding subtree.
      def legacy_conf(branding)
        {
          'brand' => {},
          'site' => {
            'interface' => { 'ui' => { 'header' => { 'branding' => branding } } },
          },
        }
      end

      context 'product_name' do
        it 'adopts SITE_NAME when BRAND_PRODUCT_NAME is unset' do
          brand = normalized({ 'brand' => {} }, 'SITE_NAME' => 'Legacy Name')
          expect(brand['product_name']).to eq('Legacy Name')
        end

        it 'prefers BRAND_PRODUCT_NAME when both env vars are set' do
          brand = normalized({ 'brand' => {} },
                             'BRAND_PRODUCT_NAME' => 'New Name',
                             'SITE_NAME' => 'Legacy Name')
          expect(brand['product_name']).to eq('New Name')
        end

        it 'prefers a brand: YAML value over the legacy SITE_NAME env var' do
          brand = normalized({ 'brand' => { 'product_name' => 'X' } },
                             'SITE_NAME' => 'Y')
          expect(brand['product_name']).to eq('X')
        end

        it 'adopts the legacy YAML site_name when no env vars are set' do
          brand = normalized(legacy_conf('site_name' => 'Yaml Name'), {})
          expect(brand['product_name']).to eq('Yaml Name')
        end

        it 'prefers the legacy env var over the legacy YAML path' do
          brand = normalized(legacy_conf('site_name' => 'Yaml Name'),
                             'SITE_NAME' => 'Env Name')
          expect(brand['product_name']).to eq('Env Name')
        end
      end

      context 'logo_url' do
        it 'adopts LOGO_URL when BRAND_LOGO_URL is unset' do
          brand = normalized({ 'brand' => {} }, 'LOGO_URL' => '/img/legacy.png')
          expect(brand['logo_url']).to eq('/img/legacy.png')
        end

        it 'prefers BRAND_LOGO_URL when both env vars are set' do
          brand = normalized({ 'brand' => {} },
                             'BRAND_LOGO_URL' => 'https://cdn.example.com/new.svg',
                             'LOGO_URL' => '/img/legacy.png')
          expect(brand['logo_url']).to eq('https://cdn.example.com/new.svg')
        end

        it 'never adopts the DefaultLogo.vue sentinel from the env var' do
          # The legacy LOGO_URL default is a Vue component reference, not an
          # asset URL — adopting it would break consumers like mail templates.
          brand = normalized({ 'brand' => {} }, 'LOGO_URL' => 'DefaultLogo.vue')
          expect(brand['logo_url']).to be_nil
        end

        it 'never adopts any *.vue component reference' do
          brand = normalized({ 'brand' => {} }, 'LOGO_URL' => 'CustomLogo.vue')
          expect(brand['logo_url']).to be_nil
        end

        it 'rejects a blank LOGO_URL' do
          brand = normalized({ 'brand' => {} }, 'LOGO_URL' => '   ')
          expect(brand['logo_url']).to be_nil
        end

        it 'adopts a usable value from the legacy YAML path' do
          brand = normalized(legacy_conf('logo' => { 'url' => '/img/yaml.png' }), {})
          expect(brand['logo_url']).to eq('/img/yaml.png')
        end

        it 'never adopts the sentinel from the legacy YAML path either' do
          brand = normalized(legacy_conf('logo' => { 'url' => 'DefaultLogo.vue' }), {})
          expect(brand['logo_url']).to be_nil
        end

        it 'rejects a *.vue value even from the BRAND_LOGO_URL authority itself' do
          # Hazard 1 (#3612) applies to every source: a component reference is
          # a frontend-only sentinel, never an asset URL for emails/favicons.
          brand = normalized({ 'brand' => {} }, 'BRAND_LOGO_URL' => 'DefaultLogo.vue')
          expect(brand['logo_url']).to be_nil
        end

        it 'rejects a *.vue value supplied via brand: YAML' do
          brand = normalized({ 'brand' => { 'logo_url' => 'LegacyLogo.vue' } }, {})
          expect(brand['logo_url']).to be_nil
        end

        it 'falls back to a usable legacy LOGO_URL when the brand value was a sentinel' do
          brand = normalized({ 'brand' => {} },
                             'BRAND_LOGO_URL' => 'DefaultLogo.vue',
                             'LOGO_URL' => 'https://cdn.example.com/l.png')
          expect(brand['logo_url']).to eq('https://cdn.example.com/l.png')
        end
      end

      context 'logo_alt' do
        it 'adopts LOGO_ALT when BRAND_LOGO_ALT is unset' do
          brand = normalized({ 'brand' => {} }, 'LOGO_ALT' => 'Legacy Alt')
          expect(brand['logo_alt']).to eq('Legacy Alt')
        end

        it 'prefers BRAND_LOGO_ALT when both env vars are set' do
          brand = normalized({ 'brand' => {} },
                             'BRAND_LOGO_ALT' => 'New Alt',
                             'LOGO_ALT' => 'Legacy Alt')
          expect(brand['logo_alt']).to eq('New Alt')
        end

        it 'adopts the legacy YAML logo alt when no env vars are set' do
          brand = normalized(legacy_conf('logo' => { 'alt' => 'Yaml Alt' }), {})
          expect(brand['logo_alt']).to eq('Yaml Alt')
        end

        it 'prefers the legacy env var over the legacy YAML path' do
          brand = normalized(legacy_conf('logo' => { 'alt' => 'Yaml Alt' }),
                             'LOGO_ALT' => 'Env Alt')
          expect(brand['logo_alt']).to eq('Env Alt')
        end
      end

      it 'keeps identity keys nil when nothing is configured (default posture)' do
        # An unconfigured install must stay neutral: no env, no YAML branding
        # means no product name / logo leaks in from anywhere (#3612).
        brand = normalized({ 'brand' => {} }, {})
        expect(brand['product_name']).to be_nil
        expect(brand['logo_url']).to be_nil
        expect(brand['logo_alt']).to be_nil
      end

      it 'tolerates a malformed legacy subtree (scalar where a hash is expected)' do
        # A hand-edited config with e.g. `branding: { logo: "oops" }` must not
        # abort boot with a TypeError from Hash#dig — an unreadable optional
        # fallback source simply reads as absent.
        brand = nil
        expect {
          brand = normalized(legacy_conf('logo' => 'oops-not-a-hash'), {})
        }.not_to raise_error
        expect(brand['logo_url']).to be_nil
      end
    end
  end

  describe '.normalize_header_layout' do
    def header_conf(header)
      { 'site' => { 'interface' => { 'ui' => { 'header' => header } } } }
    end

    def header_of(conf)
      conf.dig('site', 'interface', 'ui', 'header')
    end

    it 'deletes the legacy branding subtree' do
      conf = header_conf('branding' => { 'site_name' => 'Legacy' })
      described_class.normalize_header_layout(conf)
      expect(header_of(conf)).not_to have_key('branding')
    end

    it 'migrates branding.logo.link_to to header.logo.href when href is nil' do
      conf = header_conf('branding' => { 'logo' => { 'link_to' => '/legacy' } })
      described_class.normalize_header_layout(conf)
      expect(header_of(conf).dig('logo', 'href')).to eq('/legacy')
    end

    it 'does not overwrite an already-set header.logo.href' do
      conf = header_conf(
        'logo' => { 'href' => '/new' },
        'branding' => { 'logo' => { 'link_to' => '/legacy' } },
      )
      described_class.normalize_header_layout(conf)
      expect(header_of(conf).dig('logo', 'href')).to eq('/new')
    end

    it 'migrates show_name and prominent only where the new value is nil' do
      conf = header_conf(
        'logo' => { 'show_name' => false },
        'branding' => { 'logo' => { 'show_name' => true, 'prominent' => true } },
      )
      described_class.normalize_header_layout(conf)
      expect(header_of(conf).dig('logo', 'show_name')).to be(false)
      expect(header_of(conf).dig('logo', 'prominent')).to be(true)
    end

    it 'migrates a legacy boolean false (non-nil legacy values are honored)' do
      conf = header_conf('branding' => { 'logo' => { 'show_name' => false } })
      described_class.normalize_header_layout(conf)
      expect(header_of(conf).dig('logo', 'show_name')).to be(false)
    end

    it 'is a no-op when the header block is absent' do
      conf = { 'site' => { 'interface' => { 'ui' => {} } } }
      expect { described_class.normalize_header_layout(conf) }.not_to raise_error
      expect(conf).to eq('site' => { 'interface' => { 'ui' => {} } })
    end

    it 'strips a branding subtree that has no logo hash without adding one' do
      conf = header_conf('branding' => { 'site_name' => 'Legacy' })
      described_class.normalize_header_layout(conf)
      expect(header_of(conf)).not_to have_key('branding')
      expect(header_of(conf)).not_to have_key('logo')
    end
  end
end
