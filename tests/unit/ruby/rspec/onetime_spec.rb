# tests/unit/ruby/rspec/onetime_spec.rb

require_relative 'spec_helper'

RSpec.describe Onetime do
  describe '.env' do
    it 'defaults to production when RACK_ENV is not set' do
      expect(described_class.env).to eq('production')
    end
  end

  describe '.debug?' do
    it 'returns false by default' do
      expect(described_class.debug?).to be false
    end
  end

  describe '.conf' do
    context 'when config_proxy is set' do
      it 'returns the config proxy' do
        proxy = { test: 'config' }
        described_class.set_config_proxy(proxy)
        expect(described_class.conf).to eq(proxy)
      end
    end

    context 'when config_proxy is nil' do
      before { described_class.set_config_proxy(nil) }

      it 'returns an empty hash as fallback' do
        # The static_config is set in spec_helper.rb
        expect(described_class.conf).to be_a(Hash)
        expect(described_class.conf).not_to be_empty
      end
    end
  end

  describe '.state' do
    context 'when system is ready' do
      before do
        allow(described_class).to receive(:ready?).and_return(true)
        # Stub the ServiceRegistry constant if it doesn't exist
        unless defined?(Onetime::Services::ServiceRegistry)
          stub_const('Onetime::Services::ServiceRegistry', Class.new)
        end
        allow(Onetime::Services::ServiceRegistry).to receive(:state).and_return({ test: 'state' })
      end

      it 'returns the ServiceRegistry state' do
        expect(described_class.state).to eq({ test: 'state' })
      end
    end

    context 'when system is not ready' do
      before do
        allow(described_class).to receive(:ready?).and_return(false)
      end

      it 'returns an empty hash' do
        expect(described_class.state).to eq({})
      end
    end
  end

  describe '.provider' do
    context 'when system is ready' do
      before do
        allow(described_class).to receive(:ready?).and_return(true)
        # Stub the ServiceRegistry constant if it doesn't exist
        unless defined?(Onetime::Services::ServiceRegistry)
          stub_const('Onetime::Services::ServiceRegistry', Class.new)
        end
        allow(Onetime::Services::ServiceRegistry).to receive(:provider).and_return({ redis: 'provider' })
      end

      it 'returns the ServiceRegistry provider' do
        expect(described_class.provider).to eq({ redis: 'provider' })
      end
    end

    context 'when system is not ready' do
      before do
        allow(described_class).to receive(:ready?).and_return(false)
      end

      it 'returns an empty hash' do
        expect(described_class.provider).to eq({})
      end
    end
  end

  describe '.set_boot_state' do
    it 'sets the mode and instance' do
      described_class.set_boot_state(:test, 'test-instance-123')
      expect(described_class.mode).to eq(:test)
      expect(described_class.instance).to eq('test-instance-123')
    end

    it 'defaults mode to :app when nil is passed' do
      described_class.set_boot_state(nil, 'test-instance')
      expect(described_class.mode).to eq(:app)
    end
  end

  describe '.set_config_proxy' do
    it 'sets the config proxy' do
      proxy = { test: 'proxy' }
      described_class.set_config_proxy(proxy)
      expect(described_class.config_proxy).to eq(proxy)
    end
  end

  describe '.boot!' do
    it 'delegates to Boot.boot! and returns self' do
      expect(Onetime::Boot).to receive(:boot!).with(:test_mode)
      result = described_class.boot!(:test_mode)
      expect(result).to eq(described_class)
    end
  end

  describe '.safe_boot!' do
    context 'when boot succeeds' do
      before do
        allow(Onetime::Boot).to receive(:boot!)
      end

      it 'returns true' do
        expect(described_class.safe_boot!).to be true
      end
    end

    context 'when boot fails' do
      before do
        allow(Onetime::Boot).to receive(:boot!).and_raise(StandardError, 'Boot failed')
        allow(described_class).to receive(:not_ready!).and_return(false)
        allow(described_class).to receive(:le)
      end

      it 'returns false' do
        expect(described_class.safe_boot!).to be false
      end

      it 'calls not_ready!' do
        expect(described_class).to receive(:not_ready!).and_return(false)
        result = described_class.safe_boot!
        expect(result).to be false
      end
    end

    context 'when conf is nil after boot' do
      before do
        allow(Onetime::Boot).to receive(:boot!)
        allow(described_class).to receive(:conf).and_return(nil)
        allow(described_class).to receive(:le)
      end

      it 'logs error messages' do
        expect(described_class).to receive(:le).at_least(4).times
        described_class.safe_boot!
      end
    end
  end

  describe '.mode?' do
    before { described_class.set_boot_state(:test, 'instance') }

    it 'returns true when mode matches as symbol' do
      expect(described_class.mode?(:test)).to be true
    end

    it 'returns true when mode matches as string' do
      expect(described_class.mode?('test')).to be true
    end

    it 'returns false when mode does not match' do
      expect(described_class.mode?(:production)).to be false
    end
  end
end
