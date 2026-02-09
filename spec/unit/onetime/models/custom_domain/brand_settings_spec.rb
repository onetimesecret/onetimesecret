# spec/unit/onetime/models/custom_domain/brand_settings_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::CustomDomain::BrandSettings do
  describe 'Data class definition' do
    it 'is a Data class' do
      expect(described_class).to be < Data
    end

    it 'defines expected members' do
      expected_members = %i[
        logo
        primary_color
        product_name
        product_domain
        support_email
        footer_text
        description
        logo_url
        logo_dark_url
        favicon_url
        instructions_pre_reveal
        instructions_reveal
        instructions_post_reveal
        button_text_light
        font_family
        corner_style
        allow_public_homepage
        allow_public_api
        locale
        default_ttl
        passphrase_required
        notify_enabled
      ]
      expect(described_class.members).to match_array(expected_members)
    end
  end

  describe 'constants' do
    describe 'DEFAULTS' do
      it 'defines default values' do
        expect(described_class::DEFAULTS).to include(
          font_family: 'sans',
          corner_style: 'rounded',
          primary_color: '#dc4a22'
        )
      end

      it 'is frozen' do
        expect(described_class::DEFAULTS).to be_frozen
      end
    end

    describe 'FONTS' do
      it 'includes valid font families' do
        expect(described_class::FONTS).to contain_exactly('sans', 'serif', 'mono')
      end

      it 'is frozen' do
        expect(described_class::FONTS).to be_frozen
      end
    end

    describe 'CORNERS' do
      it 'includes valid corner styles' do
        expect(described_class::CORNERS).to contain_exactly('rounded', 'square', 'pill')
      end

      it 'is frozen' do
        expect(described_class::CORNERS).to be_frozen
      end
    end
  end

  describe '.from_hash' do
    it 'creates instance from hash with symbol keys' do
      settings = described_class.from_hash(primary_color: '#FF0000', font_family: 'serif')

      expect(settings.primary_color).to eq('#FF0000')
      expect(settings.font_family).to eq('serif')
    end

    it 'creates instance from hash with string keys' do
      settings = described_class.from_hash('primary_color' => '#00FF00', 'corner_style' => 'pill')

      expect(settings.primary_color).to eq('#00FF00')
      expect(settings.corner_style).to eq('pill')
    end

    it 'applies defaults for missing keys' do
      settings = described_class.from_hash({})

      expect(settings.font_family).to eq('sans')
      expect(settings.corner_style).to eq('rounded')
      # primary_color comes from config at runtime, falls back to #dc4a22
      expect(settings.primary_color).to be_a(String)
      expect(settings.primary_color).to match(/^#[A-Fa-f0-9]{6}$/)
    end

    it 'ignores invalid keys' do
      settings = described_class.from_hash(invalid_key: 'ignored', font_family: 'mono')

      expect(settings.font_family).to eq('mono')
      expect(settings).not_to respond_to(:invalid_key)
    end

    it 'handles nil input' do
      settings = described_class.from_hash(nil)

      expect(settings.font_family).to eq('sans')
    end

    it 'handles empty hash' do
      settings = described_class.from_hash({})

      expect(settings).to be_a(described_class)
    end
  end

  describe '#to_h_for_storage' do
    it 'converts to hash with string keys and JSON-encoded values' do
      settings = described_class.from_hash(
        primary_color: '#FF0000',
        allow_public_homepage: true
      )

      storage_hash = settings.to_h_for_storage

      # String keys for Redis compatibility
      expect(storage_hash['primary_color']).to eq('"#FF0000"')
      expect(storage_hash['allow_public_homepage']).to eq('true')
    end

    it 'excludes nil values' do
      settings = described_class.from_hash(primary_color: '#FF0000')

      storage_hash = settings.to_h_for_storage

      expect(storage_hash).not_to have_key('logo')
      expect(storage_hash).not_to have_key('instructions_pre_reveal')
    end

    it 'JSON-encodes boolean values' do
      settings = described_class.from_hash(
        button_text_light: false,
        allow_public_api: true
      )

      storage_hash = settings.to_h_for_storage

      # Booleans are JSON-encoded as literal true/false
      expect(storage_hash['button_text_light']).to eq('false')
      expect(storage_hash['allow_public_api']).to eq('true')
    end
  end

  describe '#allow_public_homepage?' do
    it 'returns true when value is string "true"' do
      settings = described_class.from_hash(allow_public_homepage: 'true')
      expect(settings.allow_public_homepage?).to be true
    end

    it 'returns true when value is boolean true' do
      settings = described_class.from_hash(allow_public_homepage: true)
      expect(settings.allow_public_homepage?).to be true
    end

    it 'returns false when value is string "false"' do
      settings = described_class.from_hash(allow_public_homepage: 'false')
      expect(settings.allow_public_homepage?).to be false
    end

    it 'returns false when value is boolean false' do
      settings = described_class.from_hash(allow_public_homepage: false)
      expect(settings.allow_public_homepage?).to be false
    end

    it 'returns false when value is nil' do
      settings = described_class.from_hash({})
      expect(settings.allow_public_homepage?).to be false
    end
  end

  describe '#allow_public_api?' do
    it 'returns true when value is string "true"' do
      settings = described_class.from_hash(allow_public_api: 'true')
      expect(settings.allow_public_api?).to be true
    end

    it 'returns true when value is boolean true' do
      settings = described_class.from_hash(allow_public_api: true)
      expect(settings.allow_public_api?).to be true
    end

    it 'returns false when value is string "false"' do
      settings = described_class.from_hash(allow_public_api: 'false')
      expect(settings.allow_public_api?).to be false
    end

    it 'returns false when value is nil' do
      settings = described_class.from_hash({})
      expect(settings.allow_public_api?).to be false
    end
  end

  describe 'validation class methods' do
    describe '.valid_color?' do
      it 'accepts valid 6-digit hex colors' do
        expect(described_class.valid_color?('#FF0000')).to be true
        expect(described_class.valid_color?('#dc4a22')).to be true
        expect(described_class.valid_color?('#123ABC')).to be true
      end

      it 'accepts valid 3-digit hex colors' do
        expect(described_class.valid_color?('#F00')).to be true
        expect(described_class.valid_color?('#abc')).to be true
      end

      it 'rejects invalid colors' do
        expect(described_class.valid_color?('FF0000')).to be false
        expect(described_class.valid_color?('#GGGGGG')).to be false
        expect(described_class.valid_color?('red')).to be false
        expect(described_class.valid_color?('')).to be false
        expect(described_class.valid_color?(nil)).to be false
      end
    end

    describe '.valid_font?' do
      it 'accepts valid font families' do
        expect(described_class.valid_font?('sans')).to be true
        expect(described_class.valid_font?('serif')).to be true
        expect(described_class.valid_font?('mono')).to be true
      end

      it 'accepts case-insensitive input' do
        expect(described_class.valid_font?('SANS')).to be true
        expect(described_class.valid_font?('Serif')).to be true
      end

      it 'rejects invalid fonts' do
        expect(described_class.valid_font?('comic-sans')).to be false
        expect(described_class.valid_font?('')).to be false
        expect(described_class.valid_font?(nil)).to be false
      end
    end

    describe '.valid_corner_style?' do
      it 'accepts valid corner styles' do
        expect(described_class.valid_corner_style?('rounded')).to be true
        expect(described_class.valid_corner_style?('square')).to be true
        expect(described_class.valid_corner_style?('pill')).to be true
      end

      it 'accepts case-insensitive input' do
        expect(described_class.valid_corner_style?('ROUNDED')).to be true
        expect(described_class.valid_corner_style?('Pill')).to be true
      end

      it 'rejects invalid corner styles' do
        expect(described_class.valid_corner_style?('circular')).to be false
        expect(described_class.valid_corner_style?('')).to be false
        expect(described_class.valid_corner_style?(nil)).to be false
      end
    end

    describe '.valid_url?' do
      it 'accepts valid HTTPS URLs' do
        expect(described_class.valid_url?('https://example.com/logo.png')).to be true
        expect(described_class.valid_url?('https://cdn.example.com/images/logo.svg')).to be true
      end

      it 'accepts relative paths starting with /' do
        expect(described_class.valid_url?('/images/logo.png')).to be true
        expect(described_class.valid_url?('/assets/favicon.ico')).to be true
      end

      it 'rejects HTTP URLs (non-HTTPS)' do
        expect(described_class.valid_url?('http://example.com/logo.png')).to be false
      end

      it 'rejects URLs without protocol' do
        expect(described_class.valid_url?('example.com/logo.png')).to be false
        expect(described_class.valid_url?('//cdn.example.com/logo.png')).to be false
      end

      it 'rejects URLs exceeding 2048 characters' do
        long_url = 'https://example.com/' + ('a' * 2048)
        expect(described_class.valid_url?(long_url)).to be false
      end

      it 'rejects empty and nil values' do
        expect(described_class.valid_url?('')).to be false
        expect(described_class.valid_url?(nil)).to be false
      end

      it 'rejects malformed URLs' do
        expect(described_class.valid_url?('not a url')).to be false
        expect(described_class.valid_url?('https://')).to be false
      end
    end
  end

  describe '.validate!' do
    it 'accepts valid settings' do
      expect do
        described_class.validate!(
          primary_color: '#FF0000',
          font_family: 'sans',
          corner_style: 'rounded',
          logo_url: 'https://example.com/logo.png',
          default_ttl: 3600
        )
      end.not_to raise_error
    end

    it 'raises on invalid primary_color' do
      expect do
        described_class.validate!(primary_color: 'red')
      end.to raise_error(Onetime::Problem, /Invalid primary color format/)
    end

    it 'raises on invalid font_family' do
      expect do
        described_class.validate!(font_family: 'comic-sans')
      end.to raise_error(Onetime::Problem, /Invalid font family/)
    end

    it 'raises on invalid corner_style' do
      expect do
        described_class.validate!(corner_style: 'circular')
      end.to raise_error(Onetime::Problem, /Invalid corner style/)
    end

    it 'raises on invalid logo_url (HTTP)' do
      expect do
        described_class.validate!(logo_url: 'http://example.com/logo.png')
      end.to raise_error(Onetime::Problem, /Invalid logo url/)
    end

    it 'raises on invalid logo_dark_url' do
      expect do
        described_class.validate!(logo_dark_url: 'not a url')
      end.to raise_error(Onetime::Problem, /Invalid logo dark url/)
    end

    it 'raises on invalid favicon_url' do
      expect do
        described_class.validate!(favicon_url: '//cdn.example.com/favicon.ico')
      end.to raise_error(Onetime::Problem, /Invalid favicon url/)
    end

    it 'raises on invalid default_ttl (string)' do
      expect do
        described_class.validate!(default_ttl: 'not a number')
      end.to raise_error(Onetime::Problem, /Invalid default TTL/)
    end

    it 'raises on invalid default_ttl (negative)' do
      expect do
        described_class.validate!(default_ttl: -100)
      end.to raise_error(Onetime::Problem, /Invalid default TTL/)
    end

    it 'accepts relative URLs for logo fields' do
      expect do
        described_class.validate!(
          logo_url: '/images/logo.png',
          logo_dark_url: '/images/logo-dark.png',
          favicon_url: '/favicon.ico'
        )
      end.not_to raise_error
    end

    it 'accepts nil values (no validation on nil)' do
      expect do
        described_class.validate!(
          primary_color: nil,
          logo_url: nil,
          default_ttl: nil
        )
      end.not_to raise_error
    end

    it 'accepts empty hash' do
      expect do
        described_class.validate!({})
      end.not_to raise_error
    end

    it 'accepts nil' do
      expect do
        described_class.validate!(nil)
      end.not_to raise_error
    end

    context 'WCAG accessibility validation' do
      it 'accepts colors with sufficient contrast (OTS orange)' do
        expect do
          described_class.validate!(primary_color: '#dc4a22')
        end.not_to raise_error
      end

      it 'accepts dark colors with high contrast' do
        expect do
          described_class.validate!(primary_color: '#000080')
        end.not_to raise_error
      end

      it 'rejects very light colors (insufficient contrast)' do
        expect do
          described_class.validate!(primary_color: '#F0F0F0')
        end.to raise_error(Onetime::Problem, /WCAG AA accessibility/)
      end

      it 'rejects light gray' do
        expect do
          described_class.validate!(primary_color: '#E0E0E0')
        end.to raise_error(Onetime::Problem, /contrast.*with white/)
      end

      it 'error message includes contrast ratio' do
        expect do
          described_class.validate!(primary_color: '#EEEEEE')
        end.to raise_error(Onetime::Problem, /contrast \d+\.\d+:1/)
      end

      it 'error message includes minimum requirements' do
        expect do
          described_class.validate!(primary_color: '#F5F5F5')
        end.to raise_error(Onetime::Problem, /minimum 3:1/)
      end

      it 'skips validation when primary_color is nil' do
        expect do
          described_class.validate!(font_family: 'sans')
        end.not_to raise_error
      end
    end
  end

  describe '.contrast_ratio' do
    it 'calculates correct ratio for black and white' do
      ratio = described_class.contrast_ratio('#000000', '#FFFFFF')
      expect(ratio.round(2)).to eq(21.0)
    end

    it 'is symmetric' do
      ratio1 = described_class.contrast_ratio('#FF0000', '#FFFFFF')
      ratio2 = described_class.contrast_ratio('#FFFFFF', '#FF0000')
      expect((ratio1 - ratio2).abs).to be < 0.01
    end

    it 'returns 1.0 for identical colors' do
      ratio = described_class.contrast_ratio('#FF0000', '#FF0000')
      expect(ratio.round(2)).to eq(1.0)
    end

    it 'handles 3-digit hex colors' do
      ratio1 = described_class.contrast_ratio('#F00', '#FFF')
      ratio2 = described_class.contrast_ratio('#FF0000', '#FFFFFF')
      expect((ratio1 - ratio2).abs).to be < 0.01
    end
  end

  describe '.relative_luminance' do
    it 'returns 0.0 for black' do
      expect(described_class.relative_luminance('#000000')).to eq(0.0)
    end

    it 'returns 1.0 for white' do
      expect(described_class.relative_luminance('#FFFFFF')).to eq(1.0)
    end

    it 'handles 3-digit hex colors' do
      l1 = described_class.relative_luminance('#F00')
      l2 = described_class.relative_luminance('#FF0000')
      expect((l1 - l2).abs).to be < 0.001
    end
  end

  describe 'immutability' do
    it 'is frozen after creation' do
      settings = described_class.from_hash(font_family: 'sans')
      expect(settings).to be_frozen
    end
  end

  describe 'pattern matching' do
    it 'supports pattern matching' do
      settings = described_class.from_hash(
        primary_color: '#FF0000',
        font_family: 'serif'
      )

      result = case settings
               in { primary_color: color, font_family: 'serif' }
                 "Serif with #{color}"
               else
                 'Other'
               end

      expect(result).to eq('Serif with #FF0000')
    end
  end

  describe 'privacy defaults' do
    describe 'default values' do
      it 'sets privacy defaults when creating empty hash' do
        settings = described_class.from_hash({})

        expect(settings.default_ttl).to be_nil
        expect(settings.passphrase_required).to be false
        expect(settings.notify_enabled).to be false
      end

      it 'applies custom privacy values' do
        settings = described_class.from_hash(
          default_ttl: 3600,
          passphrase_required: true,
          notify_enabled: true
        )

        expect(settings.default_ttl).to eq(3600)
        expect(settings.passphrase_required).to be true
        expect(settings.notify_enabled).to be true
      end
    end

    describe '#passphrase_required?' do
      it 'returns true when value is string "true"' do
        settings = described_class.from_hash(passphrase_required: 'true')
        expect(settings.passphrase_required?).to be true
      end

      it 'returns true when value is boolean true' do
        settings = described_class.from_hash(passphrase_required: true)
        expect(settings.passphrase_required?).to be true
      end

      it 'returns false when value is string "false"' do
        settings = described_class.from_hash(passphrase_required: 'false')
        expect(settings.passphrase_required?).to be false
      end

      it 'returns false when value is nil' do
        settings = described_class.from_hash({})
        expect(settings.passphrase_required?).to be false
      end
    end

    describe '#notify_enabled?' do
      it 'returns true when value is string "true"' do
        settings = described_class.from_hash(notify_enabled: 'true')
        expect(settings.notify_enabled?).to be true
      end

      it 'returns true when value is boolean true' do
        settings = described_class.from_hash(notify_enabled: true)
        expect(settings.notify_enabled?).to be true
      end

      it 'returns false when value is string "false"' do
        settings = described_class.from_hash(notify_enabled: 'false')
        expect(settings.notify_enabled?).to be false
      end

      it 'returns false when value is nil' do
        settings = described_class.from_hash({})
        expect(settings.notify_enabled?).to be false
      end
    end

    describe 'default_ttl' do
      it 'accepts integer values' do
        settings = described_class.from_hash(default_ttl: 7200)
        expect(settings.default_ttl).to eq(7200)
      end

      it 'defaults to nil when not provided' do
        settings = described_class.from_hash({})
        expect(settings.default_ttl).to be_nil
      end

      it 'stores in to_h_for_storage when set' do
        settings = described_class.from_hash(default_ttl: 3600)
        storage_hash = settings.to_h_for_storage

        expect(storage_hash).to have_key('default_ttl')
        expect(storage_hash['default_ttl']).to eq('3600')
      end
    end

    describe 'privacy defaults in storage' do
      it 'stores all privacy settings when set' do
        settings = described_class.from_hash(
          default_ttl: 3600,
          passphrase_required: true,
          notify_enabled: false
        )

        storage_hash = settings.to_h_for_storage

        expect(storage_hash['default_ttl']).to eq('3600')
        expect(storage_hash['passphrase_required']).to eq('true')
        expect(storage_hash['notify_enabled']).to eq('false')
      end

      it 'excludes nil privacy values from storage' do
        settings = described_class.from_hash(passphrase_required: true)
        storage_hash = settings.to_h_for_storage

        expect(storage_hash).not_to have_key('default_ttl')
        expect(storage_hash).to have_key('passphrase_required')
      end
    end
  end
end
