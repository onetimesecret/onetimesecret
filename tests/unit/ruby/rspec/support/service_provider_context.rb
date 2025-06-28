# tests/unit/ruby/rspec/support/service_provider_context.rb

RSpec.shared_context "service_provider_context" do
  let(:registry_klass) { Onetime::Services::ServiceRegistry }

  let(:base_service_config) do
    {
      'site' => {
        'host' => 'localhost:3000',
        'ssl' => false,
        'authentication' => {
          'enabled' => true,
          'colonels' => ['CHANGEME@example.com']
        },
        'middleware' => {
          'static_files' => true,
          'utf8_sanitizer' => true
        }
      },
      'storage' => {
        'db' => {
          'connection' => {
            'url' => 'redis://localhost:6379'
          },
          'database_mapping' => {
            'session' => 1,
            'customer' => 6,
            'secret' => 8,
            'metadata' => 7,
            'feedback' => 11,
            'ratelimit' => 2,
            'custom_domain' => 6,
            'subdomain' => 6,
            'email_receipt' => 8,
            'exception_info' => 12,
            'mutable_config' => 15,
            'splittest' => 1
          }
        }
      }
    }
  end

  let(:default_mutable_config) do
    {
      'user_interface' => {
        'enabled' => true,
        'header' => {
          'enabled' => true,
          'branding' => {
            'logo' => {
              'url' => 'DefaultLogo.vue',
              'alt' => 'Share a Secret One-Time',
              'href' => '/'
            },
            'site_name' => 'OneTimeSecret'
          },
          'navigation' => {
            'enabled' => true
          }
        },
        'footer_links' => {
          'enabled' => false
        }
      },
      'features' => {
        'plans' => {
          'enabled' => false
        }
      }
    }
  end

  let(:runtime_mutable_config) do
    {
      'user_interface' => {
        'enabled' => true,
        'header' => {
          'enabled' => true,
          'branding' => {
            'logo' => {
              'url' => 'DefaultLogo.vue',
              'alt' => 'Share a Secret One-Time',
              'href' => '/'
            },
            'site_name' => 'My Test Site'
          },
          'navigation' => {
            'enabled' => true
          }
        },
        'footer_links' => {
          'enabled' => false
        }
      }
    }
  end

  # Database-focused configuration for connect_databases tests
  let(:db_config) do
    {
      storage: {
        db: {
          connection: {
            url: 'redis://localhost:6379'
          },
          database_mapping: {
            session: 1,
            customer: 6,
            secret: 8,
            metadata: 7
          }
        }
      }
    }
  end

  # Mock Redis connection for database tests
  let(:mock_redis_connection) { double('Redis', ping: 'PONG') }

  # Mock MutableConfig for runtime config tests
  let(:mock_mutable_config) do
    double('MutableConfig',
      rediskey: 'mutable_config:test123',
      safe_dump: runtime_mutable_config
    )
  end

  before do
    # Clear ServiceRegistry state between tests
    registry_klass.instance_variable_set(:@providers, Concurrent::Map.new)
    registry_klass.instance_variable_set(:@app_state, Concurrent::Map.new)

    # Stub common OT logger methods
    allow(OT).to receive(:logger).and_return(double(info: nil, debug: nil, warn: nil))
    allow(OT).to receive(:li)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:lw)
    allow(OT).to receive(:le)
    allow(OT).to receive(:info)
    allow(OT).to receive(:debug)
    allow(OT).to receive(:warn)
    allow(OT).to receive(:error)
  end
end

RSpec.shared_context "service_provider_registry_stubs" do
  before do
    # Stub registry methods commonly used in service provider tests
    allow(registry_klass).to receive(:get_state).and_return(nil)
    allow(registry_klass).to receive(:set_state)
    allow(registry_klass).to receive(:register_provider)
  end
end

RSpec.shared_context "mutable_config_stubs" do
  before do
    # Default stubbing for V2::MutableConfig
    allow(V2::MutableConfig).to receive(:current).and_return(mock_mutable_config)
    allow(V2::MutableConfig).to receive(:create).and_return(mock_mutable_config)
  end
end

RSpec.shared_context "first_boot_stubs" do
  before do
    # Stub file loading for first boot tests
    allow(OT::Configurator::Load).to receive(:yaml_load_file).and_return(default_mutable_config)

    # Stub model checking methods for detect_first_boot
    allow(V2::Metadata).to receive(:redis).and_return(double(scan_each: double(first: nil)))
    allow(V2::Customer).to receive(:values).and_return(double(element_count: 0))
    allow(V2::Session).to receive(:values).and_return(double(element_count: 0))
  end
end

RSpec.shared_context "database_connection_stubs" do
  let(:mock_model_class1) { double('ModelClass1', to_sym: :session, 'redis=': nil, redis: mock_redis_connection) }
  let(:mock_model_class2) { double('ModelClass2', to_sym: :customer, 'redis=': nil, redis: mock_redis_connection) }
  let(:mock_model_class3) { double('ModelClass3', to_sym: :unmapped_model, 'redis=': nil, redis: mock_redis_connection) }
  let(:familia_members) { [mock_model_class1, mock_model_class2, mock_model_class3] }

  before do
    # Stub Familia methods for database connection tests
    allow(Familia).to receive(:uri=)
    allow(Familia).to receive(:redis).and_return(mock_redis_connection)
    allow(Familia).to receive(:members).and_return(familia_members)
  end
end

RSpec.shared_examples "service_provider_initialization" do |expected_name, expected_type, expected_priority|
  it "initializes with correct service provider attributes" do
    expect(subject.name).to eq(expected_name)
    expect(subject.instance_variable_get(:@type)).to eq(expected_type)
    expect(subject.priority).to eq(expected_priority)
  end
end

RSpec.shared_examples "service_provider_health_check" do
  describe '#healthy?' do
    context 'when provider is running' do
      before do
        subject.instance_variable_set(:@status, Onetime::Services::ServiceProvider::STATUS_RUNNING)
        subject.instance_variable_set(:@error, nil)
      end

      it 'returns true when healthy' do
        allow(subject).to receive(:redis_available?).and_return(true) if subject.respond_to?(:redis_available?)
        expect(subject.healthy?).to be true
      end

      it 'returns false when Redis unavailable' do
        allow(subject).to receive(:redis_available?).and_return(false) if subject.respond_to?(:redis_available?)
        expect(subject.healthy?).to be false if subject.respond_to?(:redis_available?)
      end
    end

    context 'when provider is not running' do
      it 'returns false' do
        unstarted_provider = described_class.new
        expect(unstarted_provider.healthy?).to be false
      end
    end
  end
end

RSpec.shared_examples "service_provider_error_handling" do |error_scenarios|
  describe 'error handling' do
    error_scenarios.each do |scenario_name, error_setup|
      context "when #{scenario_name}" do
        before { error_setup.call }

        it 'handles the error gracefully' do
          expect { subject.start(base_service_config) }.not_to raise_error
        end
      end
    end
  end
end
