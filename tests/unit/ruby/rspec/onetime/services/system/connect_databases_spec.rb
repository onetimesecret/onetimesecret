# tests/unit/ruby/rspec/onetime/services/system/connect_databases_spec.rb

require_relative '../../../spec_helper'
require_relative '../../../support/service_provider_context'

# Load the service provider system components
require 'onetime/services/service_provider'
require 'onetime/services/system/connect_databases'

RSpec.describe 'Service Provider System' do
  include_context "service_provider_context"
  include_context "database_connection_stubs"

  describe OT::Services::System::ConnectDatabases do
    subject(:provider) { described_class.new }

    describe '#initialize' do
      it 'sets up database connection provider with high priority' do
        expect(provider.name).to eq(:connect_databases)
        expect(provider.instance_variable_get(:@type)).to eq(:connection)
        expect(provider.priority).to eq(5)
      end
    end

    describe '#start' do
      before do
        # Stub provider registration
        allow(provider).to receive(:register_provider)
      end

      it 'successfully connects all models to their databases' do
        provider.start(db_config)

        # Verify Familia.uri was set correctly
        expect(Familia).to have_received(:uri=).with('redis://localhost:6379')

        # Verify each model was connected to correct database
        expect(Familia).to have_received(:redis).with(1) # session -> 1 (from config)
        expect(Familia).to have_received(:redis).with(6) # customer -> 6 (from config)
        expect(Familia).to have_received(:redis).with(0) # unmapped_model -> 0 (default)

        # Verify redis connections were assigned to models
        expect(mock_model_class1).to have_received('redis=').with(mock_redis_connection)
        expect(mock_model_class2).to have_received('redis=').with(mock_redis_connection)
        expect(mock_model_class3).to have_received('redis=').with(mock_redis_connection)

        # Verify ping was called on each connection
        expect(mock_redis_connection).to have_received(:ping).exactly(3).times

        # Verify provider was registered as connected
        expect(provider).to have_received(:register_provider).with(:databases, :connected)
      end

      it 'uses DATABASE_IDS fallback when model not in config mapping' do
        # Add a model that exists in DATABASE_IDS but not in config
        mock_metadata_model = double('MetadataModel', to_sym: :metadata, 'redis=': nil, redis: mock_redis_connection)
        allow(Familia).to receive(:members).and_return([mock_metadata_model])

        provider.start(db_config)

        # Should use DATABASE_IDS[:metadata] = 7 from config
        expect(Familia).to have_received(:redis).with(7)
        expect(mock_metadata_model).to have_received('redis=').with(mock_redis_connection)
      end

      it 'uses DATABASE_IDS when model not in config but exists in constants' do
        # Test with a model only in DATABASE_IDS
        mock_feedback_model = double('FeedbackModel', to_sym: :feedback, 'redis=': nil, redis: mock_redis_connection)
        allow(Familia).to receive(:members).and_return([mock_feedback_model])

        provider.start(db_config)

        # Should use DATABASE_IDS[:feedback] = 11
        expect(Familia).to have_received(:redis).with(11)
        expect(mock_feedback_model).to have_received('redis=').with(mock_redis_connection)
      end

      it 'defaults to database 0 when model not found anywhere' do
        # Test with completely unmapped model
        mock_unknown_model = double('UnknownModel', to_sym: :unknown_model, 'redis=': nil, redis: mock_redis_connection)
        allow(Familia).to receive(:members).and_return([mock_unknown_model])

        provider.start(db_config)

        # Should default to database 0
        expect(Familia).to have_received(:redis).with(0)
        expect(mock_unknown_model).to have_received('redis=').with(mock_redis_connection)
      end

      it 'raises error when no Familia members are loaded' do
        allow(Familia).to receive(:members).and_return([])

        expect { provider.start(db_config) }.to raise_error(
          Onetime::Problem,
          'No known Familia members. Models need to load before calling boot!'
        )

        # Should not attempt any connections
        expect(Familia).not_to have_received(:redis)
        expect(provider).not_to have_received(:register_provider)
      end

      it 'handles Redis connection failures gracefully' do
        # Make one model's redis assignment fail
        allow(mock_model_class1).to receive('redis=').and_raise(Redis::CannotConnectError, 'Connection refused')

        expect { provider.start(db_config) }.to raise_error(Redis::CannotConnectError)

        # Should have attempted to set Familia.uri
        expect(Familia).to have_received(:uri=).with('redis://localhost:6379')

        # Should have attempted connection but failed on first model
        expect(Familia).to have_received(:redis).with(1)
      end

      it 'handles ping failures during verification' do
        allow(mock_redis_connection).to receive(:ping).and_raise(Redis::TimeoutError, 'Timeout')

        expect { provider.start(db_config) }.to raise_error(Redis::TimeoutError)

        # Should have assigned connections but failed on ping
        expect(mock_model_class1).to have_received('redis=').with(mock_redis_connection)
      end
    end

    describe '#healthy?' do
      let(:mock_redis1) { double('Redis1', ping: 'PONG') }
      let(:mock_redis2) { double('Redis2', ping: 'PONG') }
      let(:mock_redis3) { double('Redis3', ping: 'PONG') }
      let(:mock_model1) { double('Model1', redis: mock_redis1) }
      let(:mock_model2) { double('Model2', redis: mock_redis2) }
      let(:mock_model3) { double('Model3', redis: mock_redis3) }

      before do
        # Set provider status to running without actually starting it
        provider.instance_variable_set(:@status, Onetime::Services::ServiceProvider::STATUS_RUNNING)
        provider.instance_variable_set(:@error, nil)
        allow(Familia).to receive(:members).and_return([mock_model1, mock_model2, mock_model3])
      end

      it 'returns true when all sampled connections are healthy' do
        allow(Familia.members).to receive(:sample).with(3).and_return([mock_model1, mock_model2, mock_model3])

        result = provider.healthy?

        expect(result).to be true
        expect(mock_redis1).to have_received(:ping)
        expect(mock_redis2).to have_received(:ping)
        expect(mock_redis3).to have_received(:ping)
      end

      it 'returns false when a connection fails to ping' do
        allow(mock_redis2).to receive(:ping).and_raise(Redis::TimeoutError, 'Timeout')
        allow(Familia.members).to receive(:sample).with(3).and_return([mock_model1, mock_model2, mock_model3])

        result = provider.healthy?

        expect(result).to be false
        expect(mock_redis1).to have_received(:ping)
        expect(mock_redis2).to have_received(:ping)
      end

      it 'returns false when a connection returns non-PONG response' do
        allow(mock_redis1).to receive(:ping).and_return('ERROR')
        allow(Familia.members).to receive(:sample).with(3).and_return([mock_model1, mock_model2, mock_model3])

        result = provider.healthy?

        expect(result).to be false
        expect(mock_redis1).to have_received(:ping)
      end

      it 'returns false when provider is not running' do
        unstarted_provider = described_class.new
        # Provider starts with STATUS_STOPPED by default, so should be unhealthy

        result = unstarted_provider.healthy?

        expect(result).to be false
      end

      it 'handles sampling errors gracefully' do
        allow(Familia).to receive(:members).and_raise(StandardError, 'Members unavailable')

        result = provider.healthy?

        expect(result).to be false
      end

      it 'samples fewer models when less than 3 available' do
        single_model = [mock_model1]
        allow(Familia).to receive(:members).and_return(single_model)
        allow(single_model).to receive(:sample).with(3).and_return([mock_model1])

        result = provider.healthy?

        expect(result).to be true
        expect(mock_redis1).to have_received(:ping)
      end
    end

    describe 'DATABASE_IDS constant' do
      it 'defines expected database mappings for backward compatibility' do
        expected_mappings = {
          session: 1,
          splittest: 1,
          ratelimit: 2,
          custom_domain: 6,
          customer: 6,
          subdomain: 6,
          metadata: 7,
          email_receipt: 8,
          secret: 8,
          feedback: 11,
          exception_info: 12,
          mutable_config: 15,
        }

        expect(described_class::DATABASE_IDS).to eq(expected_mappings)
      end
    end

    describe 'error scenarios' do
      before do
        allow(Familia).to receive(:uri=)
        allow(provider).to receive(:register_provider)
      end

      it 'handles malformed database configuration' do
        malformed_config = { storage: { db: nil } }

        expect { provider.start(malformed_config) }.to raise_error(NoMethodError)
      end

      it 'handles missing database_mapping section' do
        config_without_mapping = {
          storage: {
            db: {
              connection: { url: 'redis://localhost:6379' },
              database_mapping: nil
            }
          }
        }

        mock_model = double('Model', to_sym: :test_model, 'redis=': nil, redis: double(ping: 'PONG'))
        allow(Familia).to receive(:members).and_return([mock_model])
        allow(Familia).to receive(:redis).and_return(double(ping: 'PONG'))

        expect { provider.start(config_without_mapping) }.to raise_error(NoMethodError)
      end
    end
  end
end
