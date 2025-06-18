# tests/unit/ruby/rspec/onetime/services/system/first_boot_spec.rb

require_relative '../../../spec_helper'

# Load the service provider system components
require 'onetime/services/service_provider'
require 'onetime/services/system/first_boot'

RSpec.describe 'Service Provider System' do
  let(:registry_klass) { Onetime::Services::ServiceRegistry }
  let(:base_config) do
    {
      'site' => {
        'host' => 'localhost:3000',
        'ssl' => false
      },
      'storage' => {
        'db' => {
          'connection' => {
            'url' => 'redis://localhost:6379'
          }
        }
      }
    }
  end
  let(:default_mutable_settings) do
    {
      'user_interface' => {
        'enabled' => true,
        'header' => {
          'branding' => {
            'site_name' => 'OneTimeSecret'
          }
        }
      },
      'features' => {
        'plans' => {
          'enabled' => false
        }
      }
    }
  end

  before do
    # Clear ServiceRegistry state between tests
    registry_klass.instance_variable_set(:@providers, Concurrent::Map.new)
    registry_klass.instance_variable_set(:@app_state, Concurrent::Map.new)
  end

  describe OT::Services::System::FirstBoot do
    subject(:provider) { described_class.new }

    before do
      allow(OT).to receive(:logger).and_return(double(info: nil, debug: nil, warn: nil))
    end

    describe '#initialize' do
      it 'sets up first boot provider with correct configuration' do
        expect(provider.name).to eq(:first_boot)
        expect(provider.instance_variable_get(:@type)).to eq(:config)
        expect(provider.priority).to eq(20)
        expect(provider.instance_variable_get(:@first_boot)).to be_nil
      end
    end

    describe 'class attributes' do
      it 'sets correct base path from environment' do
        expect(described_class.base_path).to eq(ENV.fetch('ONETIME_HOME'))
      end

      it 'sets correct mutable settings defaults path' do
        expected_path = File.join(ENV.fetch('ONETIME_HOME'), 'etc', 'mutable_settings.yaml')
        expect(described_class.mutable_settings_defaults_path).to eq(expected_path)
      end
    end

    describe '#start' do
      let(:mock_existing_settings) { double('MutableSettings', rediskey: 'mutable_settings:abc123') }

      before do
        # Stub file loading
        allow(OT::Configurator::Load).to receive(:yaml_load_file).and_return(default_mutable_settings)

        # Stub model checking methods for detect_first_boot
        allow(V2::Metadata).to receive(:redis).and_return(double(scan_each: double(first: nil)))
        allow(V2::Customer).to receive(:values).and_return(double(element_count: 0))
        allow(V2::Session).to receive(:values).and_return(double(element_count: 0))

        # Stub MutableSettings create method
        allow(V2::MutableSettings).to receive(:create).and_return(double(rediskey: 'mutable_settings:test123'))
      end

      context 'when existing mutable settings are found' do
        before do
          allow(V2::MutableSettings).to receive(:current).and_return(mock_existing_settings)
        end

        it 'uses existing mutable settings and skips creation' do
          provider.start(base_config)

          expect(V2::MutableSettings).to have_received(:current).once
          expect(V2::MutableSettings).not_to have_received(:create)
          expect(OT::Configurator::Load).not_to have_received(:yaml_load_file)
        end

        it 'logs found existing settings' do
          expect(OT).to receive(:li).with("[BOOT.first_boot] Found existing mutable settings: mutable_settings:abc123")

          provider.start(base_config)
        end
      end

      context 'when no existing mutable settings are found (first boot)' do
        let(:mock_created_settings) { double('CreatedSettings', rediskey: 'mutable_settings:xyz789') }

        before do
          allow(V2::MutableSettings).to receive(:current).and_raise(OT::RecordNotFound, 'No config stack found')
          allow(V2::MutableSettings).to receive(:create).and_return(mock_created_settings)
        end

        it 'creates initial mutable settings from YAML defaults' do
          provider.start(base_config)

          expect(V2::MutableSettings).to have_received(:current).once
          expected_path = File.join(ENV.fetch('ONETIME_HOME'), 'etc', 'mutable_settings.yaml')
          expect(OT::Configurator::Load).to have_received(:yaml_load_file).with(expected_path)

          expected_create_args = default_mutable_settings.merge(
            comment: "Initial configuration via #{expected_path}",
            custid: nil
          )
          expect(V2::MutableSettings).to have_received(:create).with(**expected_create_args)
        end

        it 'logs creation of initial settings' do
          expect(OT).to receive(:ld).with('[BOOT.first_boot] Creating initial mutable settings from YAML...')
          expect(OT).to receive(:ld).with('[BOOT.first_boot] Created initial mutable settings: mutable_settings:xyz789')

          provider.start(base_config)
        end

        it 'detects first boot correctly when no existing data' do
          # All model checks should return falsy values for first boot
          provider.start(base_config)

          # Verify first boot detection methods were called
          expect(V2::Metadata).to have_received(:redis)
          expect(V2::Customer).to have_received(:values)
          expect(V2::Session).to have_received(:values)
        end

        it 'shows first boot warning message' do
          boot_warning = <<~BOOT
            Have you run the 1452 migration yet? Run:
                  `bundle exec bin/ots migrate --run 1452`

            If you have, make sure etc/config.yaml and mutable_settings.yaml
            files exist. In a pinch you can copy the files from etc/defaults
            to etc/ (just remove the "defaults." in the name).
          BOOT

          expect(OT).to receive(:lw).with(boot_warning)

          provider.start(base_config)
        end
      end

      context 'when not first boot but no mutable settings exist' do
        before do
          # Simulate existing data (not first boot)
          allow(V2::Customer).to receive(:values).and_return(double(element_count: 5))
          allow(V2::MutableSettings).to receive(:current).and_raise(OT::RecordNotFound, 'No config stack found')
          allow(V2::MutableSettings).to receive(:create).and_return(double(rediskey: 'mutable_settings:new123'))
        end

        it 'creates mutable settings without showing first boot warning' do
          provider.start(base_config)

          expect(V2::MutableSettings).to have_received(:create)
          # Should not show the first boot warning since existing data was found
        end
      end

      context 'error handling' do
        before do
          allow(V2::MutableSettings).to receive(:current).and_raise(OT::RecordNotFound, 'No config stack found')
        end

        it 'handles Redis connection errors gracefully' do
          redis_error = Redis::CannotConnectError.new('Connection refused')
          allow(V2::MutableSettings).to receive(:create).and_raise(redis_error)

          expect(OT).to receive(:lw).with('[BOOT.first_boot] Cannot connect to Redis for mutable settings setup: Connection refused')
          expect(OT).to receive(:lw).with('[BOOT.first_boot] Falling back to YAML configuration only')
          expect(OT).to receive(:lw).with(kind_of(String)) # First boot warning message

          expect { provider.start(base_config) }.not_to raise_error
        end

        it 'handles YAML file loading errors' do
          yaml_error = Errno::ENOENT.new('No such file')
          allow(OT::Configurator::Load).to receive(:yaml_load_file).and_raise(yaml_error)

          expect(OT).to receive(:le).with(match(/\[BOOT\.first_boot\] Error during mutable settings setup: No such file/))
          expect(OT).to receive(:lw).with('[BOOT.first_boot] Falling back to YAML configuration only')
          expect(OT).to receive(:lw).with(kind_of(String)) # First boot warning message

          expect { provider.start(base_config) }.not_to raise_error
        end

        it 'handles empty default settings' do
          allow(OT::Configurator::Load).to receive(:yaml_load_file).and_return({})

          expect(OT).to receive(:le).with('[BOOT.first_boot] Error during mutable settings setup: Missing required settings')
          expect(OT).to receive(:lw).with('[BOOT.first_boot] Falling back to YAML configuration only')
          expect(OT).to receive(:lw).with(kind_of(String)) # First boot warning message

          expect { provider.start(base_config) }.not_to raise_error
        end

        it 'handles nil default settings' do
          allow(OT::Configurator::Load).to receive(:yaml_load_file).and_return(nil)

          expect(OT).to receive(:le).with('[BOOT.first_boot] Error during mutable settings setup: Missing required settings')
          expect(OT).to receive(:lw).with('[BOOT.first_boot] Falling back to YAML configuration only')
          expect(OT).to receive(:lw).with(kind_of(String)) # First boot warning message

          expect { provider.start(base_config) }.not_to raise_error
        end

        it 'handles MutableSettings creation errors' do
          creation_error = StandardError.new('Creation failed')
          allow(V2::MutableSettings).to receive(:create).and_raise(creation_error)

          expect(OT).to receive(:le).with('[BOOT.first_boot] Error during mutable settings setup: Creation failed')
          expect(OT).to receive(:lw).with('[BOOT.first_boot] Falling back to YAML configuration only')
          expect(OT).to receive(:lw).with(kind_of(String)) # First boot warning message

          expect { provider.start(base_config) }.not_to raise_error
        end
      end
    end

    describe '#detect_first_boot (tested indirectly)' do
      before do
        allow(V2::MutableSettings).to receive(:current).and_raise(OT::RecordNotFound, 'No config stack found')
        allow(V2::MutableSettings).to receive(:create).and_return(double(rediskey: 'test'))
        allow(OT::Configurator::Load).to receive(:yaml_load_file).and_return(default_mutable_settings)
      end

      it 'detects first boot when no existing data found' do
        # Mock all checks to return no existing data
        allow(V2::Metadata).to receive(:redis).and_return(double(scan_each: double(first: nil)))
        allow(V2::Customer).to receive(:values).and_return(double(element_count: 0))
        allow(V2::Session).to receive(:values).and_return(double(element_count: 0))

        # First boot warning should be shown
        expect(OT).to receive(:lw).with(kind_of(String))

        provider.start(base_config)
      end

      it 'detects not first boot when existing metadata found' do
        # Mock metadata scan to return existing data
        allow(V2::Metadata).to receive(:redis).and_return(double(scan_each: double(first: 'metadata:existing')))
        allow(V2::Customer).to receive(:values).and_return(double(element_count: 0))
        allow(V2::Session).to receive(:values).and_return(double(element_count: 0))

        # First boot warning should NOT be shown - no expectation needed

        provider.start(base_config)
      end

      it 'detects not first boot when existing customers found' do
        allow(V2::Metadata).to receive(:redis).and_return(double(scan_each: double(first: nil)))
        allow(V2::Customer).to receive(:values).and_return(double(element_count: 3))
        allow(V2::Session).to receive(:values).and_return(double(element_count: 0))

        # First boot warning should NOT be shown - no expectation means it should not happen
        provider.start(base_config)
      end

      it 'detects not first boot when existing sessions found' do
        allow(V2::Metadata).to receive(:redis).and_return(double(scan_each: double(first: nil)))
        allow(V2::Customer).to receive(:values).and_return(double(element_count: 0))
        allow(V2::Session).to receive(:values).and_return(double(element_count: 1))

        # First boot warning should NOT be shown - no expectation means it should not happen
        provider.start(base_config)
      end
    end

    describe 'integration scenarios' do
      before do
        # Stub file loading and model checking methods
        allow(OT::Configurator::Load).to receive(:yaml_load_file).and_return(default_mutable_settings)
        allow(V2::Metadata).to receive(:redis).and_return(double(scan_each: double(first: nil)))
        allow(V2::Customer).to receive(:values).and_return(double(element_count: 0))
        allow(V2::Session).to receive(:values).and_return(double(element_count: 0))
        allow(V2::MutableSettings).to receive(:create).and_return(double(rediskey: 'mutable_settings:test'))
      end

      it 'handles complete successful first boot flow' do
        # Setup first boot scenario
        allow(V2::MutableSettings).to receive(:current).and_raise(OT::RecordNotFound, 'No config stack found')

        # Expect first boot warning
        expect(OT).to receive(:lw).with(kind_of(String))

        provider.start(base_config)

        # Verify complete flow
        expect(V2::MutableSettings).to have_received(:current).once
        expect(OT::Configurator::Load).to have_received(:yaml_load_file).once
        expect(V2::MutableSettings).to have_received(:create).once
      end

      it 'handles existing installation with mutable settings' do
        # Setup existing installation
        allow(V2::Customer).to receive(:values).and_return(double(element_count: 10))
        existing_settings = double('ExistingSettings', rediskey: 'mutable_settings:existing_456')
        allow(V2::MutableSettings).to receive(:current).and_return(existing_settings)

        provider.start(base_config)

        # Should skip creation entirely
        expect(V2::MutableSettings).to have_received(:current).once
        expect(OT::Configurator::Load).not_to have_received(:yaml_load_file)
        expect(V2::MutableSettings).not_to have_received(:create)
      end
    end
  end
end
