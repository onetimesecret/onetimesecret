# tests/unit/ruby/rspec/onetime/config/apply_config_spec.rb

require_relative '../../spec_helper'

RSpec.describe Onetime::Config do
  describe '#apply_config' do
    let(:base_yaml_config) do
      {
        site: {
          interface: {
            host: 'localhost',
            port: 3000,
            ssl: false
          },
          secret_options: {
            max_size: 1024,
            default_ttl: 3600
          }
        },
        mail: {
          from: 'noreply@example.com',
          smtp: {
            host: 'smtp.example.com',
            port: 587
          }
        },
        limits: {
          create_secret: 250,
          send_feedback: 10
        },
        experimental: {
          enabled: false
        },
        diagnostics: {
          enabled: true,
          level: 'info'
        }
      }
    end

    let(:colonel_config_hash) do
      {
        interface: {
          host: 'custom.example.com',
          port: 8080,
          ssl: true
        },
        secret_options: {
          max_size: 2048
        },
        mail: {
          from: 'custom@example.com'
        },
        limits: {
          create_secret: 500
        },
        experimental: {
          enabled: true
        }
      }
    end

    let(:expected_merged_config) do
      {
        site: {
          interface: {
            host: 'custom.example.com',
            port: 8080,
            ssl: true
          },
          secret_options: {
            max_size: 2048,
            default_ttl: 3600
          }
        },
        mail: {
          from: 'custom@example.com',
          smtp: {
            host: 'smtp.example.com',
            port: 587
          }
        },
        limits: {
          create_secret: 500,
          send_feedback: 10
        },
        experimental: {
          enabled: true
        },
        diagnostics: {
          enabled: true,
          level: 'info'
        }
      }
    end

    context 'with valid configurations' do
      it 'applies base YAML config when no colonel config exists' do
        allow(V2::ColonelConfig).to receive(:current).and_raise(Onetime::RecordNotFound.new("No config found"))

        result = described_class.apply_config(base_yaml_config)
        expect(result).to eq(base_yaml_config)
      end

      it 'merges colonel config over base YAML config' do
        colonel_config = double('ColonelConfig')
        allow(V2::ColonelConfig).to receive(:current).and_return(colonel_config)
        allow(V2::ColonelConfig).to receive(:construct_onetime_config).with(colonel_config).and_return({
          site: {
            interface: { host: 'custom.example.com', port: 8080, ssl: true },
            secret_options: { max_size: 2048 }
          },
          mail: { from: 'custom@example.com' },
          limits: { create_secret: 500 },
          experimental: { enabled: true }
        })

        result = described_class.apply_config(base_yaml_config)
        expect(result).to eq(expected_merged_config)
      end

      it 'preserves YAML values not overridden by colonel config' do
        colonel_config = double('ColonelConfig')
        allow(V2::ColonelConfig).to receive(:current).and_return(colonel_config)
        allow(V2::ColonelConfig).to receive(:construct_onetime_config).with(colonel_config).and_return({
          site: { interface: { host: 'custom.example.com' } }
        })

        result = described_class.apply_config(base_yaml_config)

        expect(result[:site][:interface][:host]).to eq('custom.example.com')
        expect(result[:site][:interface][:port]).to eq(3000)
        expect(result[:site][:interface][:ssl]).to eq(false)
        expect(result[:mail]).to eq(base_yaml_config[:mail])
      end

      it 'handles nested hash merging correctly' do
        colonel_config = double('ColonelConfig')
        allow(V2::ColonelConfig).to receive(:current).and_return(colonel_config)
        allow(V2::ColonelConfig).to receive(:construct_onetime_config).with(colonel_config).and_return({
          mail: {
            smtp: { port: 465, ssl: true }
          }
        })

        result = described_class.apply_config(base_yaml_config)

        expect(result[:mail][:from]).to eq('noreply@example.com')
        expect(result[:mail][:smtp][:host]).to eq('smtp.example.com')
        expect(result[:mail][:smtp][:port]).to eq(465)
        expect(result[:mail][:smtp][:ssl]).to eq(true)
      end
    end

    context 'with edge cases' do
      it 'handles nil base config' do
        allow(V2::ColonelConfig).to receive(:current).and_raise(Onetime::RecordNotFound.new("No config found"))

        result = described_class.apply_config(nil)
        expect(result).to eq({})
      end

      it 'handles empty base config' do
        allow(V2::ColonelConfig).to receive(:current).and_raise(Onetime::RecordNotFound.new("No config found"))

        result = described_class.apply_config({})
        expect(result).to eq({})
      end

      it 'handles colonel config with nil values' do
        colonel_config = double('ColonelConfig')
        allow(V2::ColonelConfig).to receive(:current).and_return(colonel_config)
        allow(V2::ColonelConfig).to receive(:construct_onetime_config).with(colonel_config).and_return({
          site: { interface: { host: nil } },
          mail: nil
        })

        result = described_class.apply_config(base_yaml_config)

        expect(result[:site][:interface][:host]).to be_nil
        expect(result[:site][:interface][:port]).to eq(3000)
        expect(result[:mail]).to be_nil
      end

      it 'handles Redis connection errors gracefully' do
        allow(V2::ColonelConfig).to receive(:current).and_raise(Redis::BaseError.new("Connection failed"))

        result = described_class.apply_config(base_yaml_config)
        expect(result).to eq(base_yaml_config)
      end

      it 'handles colonel config parsing errors' do
        allow(V2::ColonelConfig).to receive(:current).and_raise(Onetime::Problem.new("Invalid config"))

        result = described_class.apply_config(base_yaml_config)
        expect(result).to eq(base_yaml_config)
      end

      it 'does not modify the original base config' do
        original_config = base_yaml_config.dup
        colonel_config = double('ColonelConfig')
        allow(V2::ColonelConfig).to receive(:current).and_return(colonel_config)
        allow(V2::ColonelConfig).to receive(:construct_onetime_config).with(colonel_config).and_return({
          site: { interface: { host: 'modified.example.com' } }
        })

        described_class.apply_config(base_yaml_config)
        expect(base_yaml_config).to eq(original_config)
      end
    end

    context 'with colonel config field mappings' do
      it 'correctly applies all colonel manageable sections' do
        colonel_config = double('ColonelConfig')
        allow(V2::ColonelConfig).to receive(:current).and_return(colonel_config)

        # Test all sections defined in FIELD_MAPPINGS
        colonel_overlay = {
          site: {
            interface: { host: 'colonel.example.com' },
            secret_options: { max_size: 4096 }
          },
          mail: { from: 'colonel@example.com' },
          limits: { create_secret: 1000 },
          experimental: { enabled: true },
          diagnostics: { level: 'debug' }
        }

        allow(V2::ColonelConfig).to receive(:construct_onetime_config).with(colonel_config).and_return(colonel_overlay)

        result = described_class.apply_config(base_yaml_config)

        expect(result[:site][:interface][:host]).to eq('colonel.example.com')
        expect(result[:site][:secret_options][:max_size]).to eq(4096)
        expect(result[:mail][:from]).to eq('colonel@example.com')
        expect(result[:limits][:create_secret]).to eq(1000)
        expect(result[:experimental][:enabled]).to eq(true)
        expect(result[:diagnostics][:level]).to eq('debug')
      end
    end
  end
end
