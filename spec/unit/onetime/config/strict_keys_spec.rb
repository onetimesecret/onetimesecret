# spec/unit/onetime/config/strict_keys_spec.rb
#
# frozen_string_literal: true

# Onetime::Config::StrictKeys: the test-only key check on every Hash in the
# config tree, and Onetime::Config.wrap installing it when strict_keys? is on
# (spec_helper turns it on for the suite).

require 'spec_helper'

RSpec.describe Onetime::Config::StrictKeys do
  let(:tree) do
    {
      'site' => {
        'host' => 'example.com',
        'admin' => { 'enabled' => true },
      },
      'features' => {
        'incoming' => {
          'recipients' => [{ 'email' => 'ops@example.com', 'name' => 'Ops' }],
        },
      },
    }
  end

  let(:config) { described_class.install(tree) }

  # Each checked method, called on the site section with a key, and what the
  # call returns there with the key 'host', as on a plain Hash.
  key_calls = {
    '#[]' => [->(hash, key) { hash[key] }, 'example.com'],
    '#[]=' => [->(hash, key) { hash[key] = 'example.org' }, 'example.org'],
    '#store' => [->(hash, key) { hash.store(key, 'example.org') }, 'example.org'],
    '#dig' => [->(hash, key) { hash.dig(key) }, 'example.com'], # rubocop:disable Style/SingleArgumentDig
    '#fetch' => [->(hash, key) { hash.fetch(key) }, 'example.com'],
    '#fetch with a default' => [->(hash, key) { hash.fetch(key, nil) }, 'example.com'],
    '#fetch with a block' => [->(hash, key) { hash.fetch(key) { nil } }, 'example.com'], # rubocop:disable Style/RedundantFetchBlock
    '#key?' => [->(hash, key) { hash.key?(key) }, true],
    '#has_key?' => [->(hash, key) { hash.has_key?(key) }, true], # rubocop:disable Style/PreferredHashMethods
    '#include?' => [->(hash, key) { hash.include?(key) }, true],
    '#member?' => [->(hash, key) { hash.member?(key) }, true],
  }

  key_calls.each do |name, (call, string_result)|
    describe name do
      let(:site) { config['site'] }

      it 'raises on a Symbol key, naming the key and its class' do
        expect { call.call(site, :host) }.to raise_error(
          Onetime::Config::KeyTypeError,
          'Config key :host is a Symbol; config keys are Strings',
        )
      end

      it 'raises on an Integer key' do
        expect { call.call(site, 0) }.to raise_error(Onetime::Config::KeyTypeError, /Config key 0 is a Integer/)
      end

      it 'works on a String key' do
        expect(call.call(site, 'host')).to eq(string_result)
      end
    end
  end

  describe 'Onetime::Config::KeyTypeError' do
    it 'is a TypeError and not an Onetime::Problem, as the reader errors are' do
      expect(Onetime::Config::KeyTypeError.ancestors).to include(TypeError)
      expect(Onetime::Config::KeyTypeError.ancestors).not_to include(Onetime::Problem)
    end

    it 'keeps the key' do
      expect { config[:site] }.to raise_error(Onetime::Config::KeyTypeError) { |error| expect(error.key).to eq(:site) }
    end
  end

  describe 'nested Hashes' do
    it 'checks every level' do
      expect { config[:site] }.to raise_error(Onetime::Config::KeyTypeError)
      expect { config['site'][:admin] }.to raise_error(Onetime::Config::KeyTypeError)
      expect { config['site']['admin'][:enabled] }.to raise_error(Onetime::Config::KeyTypeError)
      expect(config['site']['admin']['enabled']).to be(true)
    end

    it 'checks every key #dig reads, at any depth' do
      expect { config.dig('site', :admin) }.to raise_error(Onetime::Config::KeyTypeError, /:admin/)
      expect { config.dig('site', 'admin', :enabled) }.to raise_error(Onetime::Config::KeyTypeError, /:enabled/)
      expect(config.dig('site', 'admin', 'enabled')).to be(true)
    end

    it 'checks a Hash inside an Array' do
      recipient = config['features']['incoming']['recipients'].first

      expect { recipient[:email] }.to raise_error(Onetime::Config::KeyTypeError, /:email/)
      expect { config.dig('features', 'incoming', 'recipients', 0, :email) }
        .to raise_error(Onetime::Config::KeyTypeError, /:email/)
      expect(config.dig('features', 'incoming', 'recipients', 0, 'email')).to eq('ops@example.com')
    end

    it 'installs in place, keeping the identity of each Hash and Array' do
      recipients = tree['features']['incoming']['recipients']

      expect(config).to equal(tree)
      expect(config['features']['incoming']['recipients']).to equal(recipients)
      expect(recipients.first).to be_a(described_class)
    end
  end

  describe 'a String-keyed write' do
    it 'reads back' do
      config['site']['port'] = 443
      config['site'].store('ssl', true)

      expect(config['site']['port']).to eq(443)
      expect(config.dig('site', 'ssl')).to be(true)
    end

    it 'gives the Hashes it writes StrictKeys, including those in an Array' do
      config['site']['elevation'] = { 'enabled' => false, 'rules' => [{ 'role' => 'colonel' }] }

      expect { config['site']['elevation'][:enabled] }.to raise_error(Onetime::Config::KeyTypeError)
      expect { config.dig('site', 'elevation', 'rules', 0, :role) }.to raise_error(Onetime::Config::KeyTypeError)
      expect(config.dig('site', 'elevation', 'rules', 0, 'role')).to eq('colonel')
    end

    it 'gives the Hashes it stores StrictKeys' do
      config['site'].store('elevation', { 'enabled' => false })

      expect { config['site']['elevation'][:enabled] }.to raise_error(Onetime::Config::KeyTypeError)
    end

    it 'stores a written Hash with Symbol keys as it is' do
      config['site']['legacy'] = { enabled: true }

      expect(config['site']['legacy'].to_a).to eq([[:enabled, true]])
    end

    # Installing replaces a frozen child under its existing key, which here
    # is a Symbol: that store must not go through the key check.
    it 'installs below a Symbol key whose value is frozen' do
      config['site']['legacy'] = { legacy: { 'enabled' => true }.freeze }

      child = config['site']['legacy'].to_a.first.last
      expect(child).to be_frozen
      expect { child[:enabled] }.to raise_error(Onetime::Config::KeyTypeError)
    end
  end

  describe 'a frozen tree' do
    it 'is replaced by frozen copies that check their keys' do
      frozen = Onetime::Config.deep_freeze(
        { 'site' => { 'admin' => { 'enabled' => true } }, 'list' => [{ 'email' => 'ops@example.com' }] },
      )

      strict = described_class.install(frozen)

      expect(strict).to eq(frozen)
      expect(strict).to be_frozen
      expect(strict['site']).to be_frozen
      expect(strict['list']).to be_frozen
      expect { strict['site']['admin'][:enabled] }.to raise_error(Onetime::Config::KeyTypeError)
      expect { strict['list'].first[:email] }.to raise_error(Onetime::Config::KeyTypeError)
    end
  end

  describe 'serialization' do
    it 'survives a YAML round-trip as plain Hashes with the same contents' do
      copy = YAML.load(YAML.dump(config))

      expect(YAML.dump(config)).not_to include('!ruby')
      expect(copy).to eq(tree)
      expect(copy).not_to be_a(described_class)
      expect(copy['site'][:host]).to be_nil
    end

    it 'survives Onetime::Config.deep_clone' do
      expect(Onetime::Config.deep_clone(config)).to eq(tree)
    end

    it 'survives a Marshal round-trip, which keeps StrictKeys' do
      copy = Marshal.load(Marshal.dump(config))

      expect(copy).to eq(tree)
      expect(copy.dig('features', 'incoming', 'recipients', 0, 'email')).to eq('ops@example.com')
      expect { copy['site'][:host] }.to raise_error(Onetime::Config::KeyTypeError)
    end
  end

  describe 'Onetime::Config.wrap' do
    around do |example|
      saved = Onetime::Config.strict_keys?
      example.run
    ensure
      Onetime::Config.strict_keys = saved
    end

    context 'with strict_keys on' do
      before { Onetime::Config.strict_keys = true }

      it 'gives the root the reader and every Hash StrictKeys' do
        wrapped = Onetime::Config.wrap(tree)

        expect(wrapped).to equal(tree)
        expect(wrapped).to be_a(Onetime::Config::Reader)
        expect(wrapped.get('site.host')).to eq('example.com')
        expect { wrapped.get('site')[:host] }.to raise_error(Onetime::Config::KeyTypeError)
        expect { wrapped.get('features.incoming.recipients').first[:email] }
          .to raise_error(Onetime::Config::KeyTypeError)
      end

      it 'is idempotent' do
        once = Onetime::Config.wrap(tree)

        expect(Onetime::Config.wrap(once)).to equal(once)
      end

      it 'is idempotent on a frozen root' do
        once = Onetime::Config.wrap(Onetime::Config.deep_freeze({ 'site' => { 'host' => 'example.com' } }))

        expect(once).to be_frozen
        expect(Onetime::Config.wrap(once)).to equal(once)
        expect { once['site'][:host] }.to raise_error(Onetime::Config::KeyTypeError)
      end

      it 'checks a root that was wrapped while it was off' do
        Onetime::Config.strict_keys = false

        plain = Onetime::Config.wrap(tree)

        Onetime::Config.strict_keys = true

        expect(Onetime::Config.wrap(plain)).to equal(plain)
        expect { plain['site'][:host] }.to raise_error(Onetime::Config::KeyTypeError)
      end

      it 'is on for the suite config' do
        expect(OT.conf).to be_a(described_class)
        expect { OT.conf.get('site')[:host] }.to raise_error(Onetime::Config::KeyTypeError)
      end
    end

    context 'with strict_keys off' do
      before { Onetime::Config.strict_keys = false }

      it 'gives the root the reader and nothing else' do
        wrapped = Onetime::Config.wrap(tree)

        expect(wrapped.get('site.host')).to eq('example.com')
        expect(wrapped).not_to be_a(described_class)
        expect(wrapped['site']).not_to be_a(described_class)
        expect(wrapped['site'][:host]).to be_nil
        expect(wrapped.dig('site', :host)).to be_nil
        expect(wrapped['site'].key?(:host)).to be(false)
      end

      it 'is idempotent' do
        once = Onetime::Config.wrap(tree)

        expect(Onetime::Config.wrap(once)).to equal(once)
      end

      it 'returns a frozen wrapped config unchanged, as production holds it' do
        once = Onetime::Config.wrap(Onetime::Config.deep_freeze({ 'site' => { 'host' => 'example.com' } }))

        expect(once).to be_frozen
        expect(Onetime::Config.wrap(once)).to equal(once)
        expect(once['site']).not_to be_a(described_class)
      end
    end
  end
end
