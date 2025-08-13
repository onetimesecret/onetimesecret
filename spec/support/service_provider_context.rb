# spec/support/service_provider_context.rb

RSpec.shared_context "service_provider_context" do
  let(:base_service_config) do
    {
      'home' => ENV.fetch('ONETIME_HOME'),
      'environment' => 'test'
    }
  end

  before(:each) do
    # Mock basic logging to avoid noise in tests
    allow(OT).to receive(:li)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:lw)
    allow(OT).to receive(:le)
  end
end

RSpec.shared_context "first_boot_stubs" do
  before(:each) do
    # Mock Redis/database queries for first boot detection
    allow(V2::Metadata).to receive(:redis).and_return(double(scan_each: double(first: nil)))
    allow(V2::Customer).to receive(:values).and_return(double(element_count: 0))
    allow(V2::Session).to receive(:values).and_return(double(element_count: 0))
  end
end

RSpec.shared_context "mutable_config_stubs" do
  let(:default_mutable_config) do
    {
      'site' => {
        'host' => 'localhost:7143',
        'domain' => 'localhost',
        'ssl' => false
      },
      'emailer' => {
        'mode' => 'smtp',
        'from' => 'test@example.com'
      },
      'limits' => {
        'create_secret' => 250,
        'create_account' => 10,
        'update_account' => 10
      }
    }
  end

  before(:each) do
    # Mock YAML loading for mutable config defaults
    allow(OT::Configurator::Load).to receive(:yaml_load_file).and_return(default_mutable_config)
  end
end
