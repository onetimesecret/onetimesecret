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
      expect(settings.primary_color).to eq('#dc4a22')
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
