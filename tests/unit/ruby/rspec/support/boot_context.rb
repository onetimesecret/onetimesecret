# tests/unit/ruby/rspec/support/boot_context.rb

RSpec.shared_context "boot_context" do

  let(:load_with_impunity_config) do
    {
      site: {
        secret: 'test-secret-key-for-tests',
        authentication: {
          enabled: true,
          colonels: []
        }
      },
      development: {},
      mail: {
        connection: {},
        validation: {
          defaults: {},
        },
      },
      experimental: {
        allow_nil_global_secret: false,
      },
    }
  end

  before(:each) do
    # Ensure OT.conf returns the configured test values
    allow(OT).to receive(:conf).and_return(load_with_impunity_config)
  end

  after(:each) do
    OT.instance_variable_set(:@conf, nil)
    OT.instance_variable_set(:@global_secret, nil)
  end
end
