# spec/unit/onetime/config/reader_spec.rb
#
# frozen_string_literal: true

# OT.conf.get: the dotted-path reader on the root config Hash, and the three
# places that install it (Config.after_load, OT.conf=, the OT.conf reader).

require 'spec_helper'

RSpec.describe Onetime::Config::Reader do
  let(:config) do
    Onetime::Config.wrap(
      'site' => {
        'host' => 'example.com',
        'ssl' => false,
        'port' => 0,
        'unset' => nil,
        'admin' => nil,
        'colonels' => ['ops@example.com'],
      },
      'mail' => {
        'truemail' => { 'validation_type_for' => { 'example.com' => 'mx' } },
      },
    )
  end

  describe '#get' do
    context 'when the path resolves' do
      it 'returns the value' do
        expect(config.get('site.host')).to eq('example.com')
      end

      it 'returns a section as a Hash' do
        expect(config.get('site')).to include('host' => 'example.com')
      end

      it 'returns false and 0 as they are, ignoring the default' do
        expect(config.get('site.ssl', true)).to be(false)
        expect(config.get('site.port', 443)).to eq(0)
      end

      it 'reads a key that contains a dot through the Array form' do
        expect(config.get(%w[mail truemail validation_type_for example.com])).to eq('mx')
      end
    end

    context 'when the key is absent' do
      it 'returns the default' do
        expect(config.get('site.elevation', {})).to eq({})
      end

      it 'returns an explicit nil default' do
        expect(config.get('site.product_name', nil)).to be_nil
      end

      it 'returns a false or 0 default as given' do
        expect(config.get('site.elevation', false)).to be(false)
        expect(config.get('site.elevation', 0)).to eq(0)
      end

      it 'raises MissingPathError without a default, naming the missing segment' do
        expect { config.get('site.elevation') }.to raise_error(
          Onetime::Config::MissingPathError,
          "Config path 'site.elevation' is not set: 'site' has no 'elevation'",
        )
      end

      it 'names a missing top-level section' do
        expect { config.get('features.domains.enabled') }.to raise_error(
          Onetime::Config::MissingPathError, /there is no top-level 'features'/
        )
      end

      it 'shows a path whose segment holds a dot as its segment list' do
        expect { config.get(%w[mail truemail validation_type_for other.example]) }.to raise_error(
          Onetime::Config::MissingPathError,
          %q(Config path '["mail", "truemail", "validation_type_for", "other.example"]' is not set: ) +
            %q('mail.truemail.validation_type_for' has no 'other.example'),
        )
      end

      it 'is a KeyError that carries the path and the missing key' do
        expect { config.get('site.elevation') }.to raise_error(KeyError) { |error|
          expect(error.path).to eq(%w[site elevation])
          expect(error.key).to eq('elevation')
        }
      end

      # A rescue of Onetime::Problem around a read keeps its pre-get
      # behavior: a failed read passes through it.
      it 'is not an Onetime::Problem' do
        expect(Onetime::Config::MissingPathError.ancestors).not_to include(Onetime::Problem)
      end
    end

    context 'when an intermediate section is nil' do
      it 'returns the default' do
        expect(config.get('site.admin.elevation', {})).to eq({})
        expect(config.get('site.admin.elevation', false)).to be(false)
      end

      it 'raises MissingPathError without a default' do
        expect { config.get('site.admin.elevation') }.to raise_error(
          Onetime::Config::MissingPathError,
          "Config path 'site.admin.elevation' is not set: 'site.admin' is nil",
        )
      end
    end

    context 'when the value is nil' do
      it 'returns the default' do
        expect(config.get('site.unset', 'fallback')).to eq('fallback')
        expect(config.get('site.unset', 0)).to eq(0)
      end

      it 'returns nil without a default' do
        expect(config.get('site.unset')).to be_nil
      end
    end

    context 'when the path runs through a value that is not a Hash' do
      it 'raises PathTypeError, even with a default' do
        expect { config.get('site.host.name', 'fallback') }.to raise_error(
          Onetime::Config::PathTypeError,
          "Config path 'site.host.name' cannot be read: 'site.host' is String, not a section",
        )
      end

      it 'raises PathTypeError for an Array' do
        expect { config.get('site.colonels.first') }.to raise_error(Onetime::Config::PathTypeError)
      end

      it 'raises PathTypeError for a false value, even with a default' do
        expect { config.get('site.ssl.enabled', true) }.to raise_error(
          Onetime::Config::PathTypeError, /'site.ssl' is FalseClass, not a section/
        )
      end

      it 'is a TypeError, as dig raises, that carries the path' do
        expect { config.get('site.host.name') }.to raise_error(TypeError) { |error|
          expect(error).to be_a(Onetime::Config::PathTypeError)
          expect(error.path).to eq(%w[site host name])
        }
        expect(Onetime::Config::PathTypeError.ancestors).not_to include(Onetime::Problem)
      end
    end

    context 'with an invalid path' do
      it 'rejects an empty path' do
        expect { config.get('') }.to raise_error(ArgumentError, 'config path is empty')
        expect { config.get([]) }.to raise_error(ArgumentError, 'config path is empty')
      end

      it 'rejects an empty segment' do
        expect { config.get('site..host') }.to raise_error(ArgumentError, /segment ""/)
        expect { config.get('site.host.') }.to raise_error(ArgumentError, /segment ""/)
      end

      it 'rejects a Symbol path or segment' do
        expect { config.get(:site) }.to raise_error(ArgumentError, /not Symbol/)
        expect { config.get(['site', :host]) }.to raise_error(ArgumentError, /segment :host/)
      end

      it 'rejects an Integer segment and a nil or Integer path' do
        expect { config.get(['site', 0]) }.to raise_error(ArgumentError, /segment 0/)
        expect { config.get(nil) }.to raise_error(ArgumentError, /not NilClass/)
        expect { config.get(1) }.to raise_error(ArgumentError, /not Integer/)
      end
    end

    # A keyword default would arrive as the Hash {default: false}, which is
    # truthy: an absent boolean flag would read as enabled.
    context 'with a keyword argument' do
      it 'raises instead of returning a Hash as the default' do
        expect { config.get('site.elevation', default: false) }.to raise_error(ArgumentError, /no keywords/)
      end

      it 'still takes a Hash literal as a positional default' do
        expect(config.get('site.elevation', {})).to eq({})
        expect(config.get('site.elevation', { 'enabled' => false })).to eq('enabled' => false)
      end
    end

    it 'reads a deep-frozen config' do
      frozen = Onetime::Config.deep_freeze(Onetime::Config.wrap('site' => { 'host' => 'example.com' }))

      expect(frozen).to be_frozen
      expect(frozen.get('site.host')).to eq('example.com')
    end
  end

  describe 'Onetime::Config.wrap' do
    it 'extends a Hash in place and keeps it a Hash' do
      hash = { 'site' => { 'host' => 'example.com' } }

      wrapped = Onetime::Config.wrap(hash)

      expect(wrapped).to equal(hash)
      expect(wrapped).to be_a(Hash)
      expect(wrapped).to be_a(described_class)
    end

    it 'is idempotent' do
      once = Onetime::Config.wrap({ 'a' => 1 })

      expect(Onetime::Config.wrap(once)).to equal(once)
    end

    it 'returns a frozen wrapped Hash unchanged, as production holds it' do
      frozen = Onetime::Config.wrap({ 'a' => 1 }).freeze

      expect(Onetime::Config.wrap(frozen)).to equal(frozen)
    end

    it 'copies a frozen Hash and freezes the copy' do
      hash = { 'a' => 1 }.freeze

      wrapped = Onetime::Config.wrap(hash)

      expect(wrapped).not_to equal(hash)
      expect(wrapped).to be_frozen
      expect(wrapped).to eq(hash)
      expect(wrapped.get('a')).to eq(1)
    end

    it 'returns nil and other non-Hash values unchanged' do
      value = Object.new

      expect(Onetime::Config.wrap(nil)).to be_nil
      expect(Onetime::Config.wrap(value)).to equal(value)
    end

    it 'leaves the Hash equal to a plain Hash and serializable as one' do
      wrapped = Onetime::Config.wrap({ 'site' => { 'host' => 'example.com' } })

      expect(wrapped).to eq({ 'site' => { 'host' => 'example.com' } })
      expect(YAML.dump(wrapped)).not_to include('!ruby')
      expect(Onetime::Config.deep_clone(wrapped)).to eq(wrapped)
    end

    it 'gives the reader only to the root' do
      wrapped = Onetime::Config.wrap({ 'site' => { 'host' => 'example.com' } })

      expect(wrapped.get('site')).not_to respond_to(:get)
    end
  end

  describe 'install points' do
    around do |example|
      saved = OT.instance_variable_get(:@conf)
      example.run
    ensure
      OT.instance_variable_set(:@conf, saved)
    end

    it 'Config.after_load returns a config that answers #get' do
      result = Onetime::Config.after_load(
        'site' => { 'secret' => 'test-secret', 'host' => 'example.com' },
        'mail' => { 'truemail' => {} },
        'compatibility' => { 'deprecated_config_mode' => 'silent' },
      )

      expect(result).to be_a(described_class)
      expect(result.get('site.host')).to eq('example.com')
    end

    it 'OT.replace_config! wraps the Hash it installs' do
      OT.replace_config!('site' => { 'host' => 'example.com' })

      expect(OT.instance_variable_get(:@conf)).to be_a(described_class)
      expect(OT.conf.get('site.host')).to eq('example.com')
    end

    it 'the OT.conf reader wraps a Hash set directly on @conf' do
      OT.instance_variable_set(:@conf, { 'site' => { 'host' => 'example.com' } })

      expect(OT.conf.get('site.host')).to eq('example.com')
      expect(OT.conf).to equal(OT.conf)
    end

    it 'the OT.conf reader stores the wrapped copy of a frozen Hash' do
      OT.instance_variable_set(:@conf, { 'site' => { 'host' => 'example.com' } }.freeze)

      first = OT.conf

      expect(first).to be_a(described_class)
      expect(OT.conf).to equal(first)
      expect(OT.instance_variable_get(:@conf)).to equal(first)
    end

    it 'the OT.conf reader returns nil before a config is installed' do
      OT.instance_variable_set(:@conf, nil)

      expect(OT.conf).to be_nil
    end

    it 'the suite config answers #get' do
      expect(OT.conf).to be_a(described_class)
    end
  end
end
