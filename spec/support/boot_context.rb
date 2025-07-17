# spec/support/boot_context.rb

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
    # Mock OT.conf to return the configured test values
    allow(OT).to receive(:conf).and_return(load_with_impunity_config)

    # Mock OT.state to return an empty hash by default
    # Individual tests can override this as needed
    allow(OT).to receive(:state).and_return({})
  end

  after(:each) do
    # Reset any state that may have been set during tests
    # Since we're mocking, we don't need to clean up instance variables

    # If any tests modified the global state directly, reset it
    if OT.respond_to?(:state) && OT.state.is_a?(Hash)
      OT.state.clear
    end
  end
end
