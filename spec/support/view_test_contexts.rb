# spec/support/view_test_contexts.rb
#
# frozen_string_literal: true

# Shared context for Rack::Test integration with mocked request/response
RSpec.shared_context "rack_test_context" do
  let(:rack_request) do
    instance_double(Rack::Request,
      params: {},
      get?: false,
      post?: false,
      path_info: '/test',
      env: {
        'REMOTE_ADDR' => '127.0.0.1',
        'HTTP_HOST' => 'example.com',
        'rack.session' => {},
        'HTTP_ACCEPT' => 'application/json',
        'ots.locale' => 'en',
      },
      cookies: {},
      session: {},
      script_name: '',
      body: StringIO.new)
  end

  let(:rack_response) do
    instance_double(Rack::Response,
      status: 200,
      headers: {},
      header: {},
      body: [],
      set_cookie: nil,
      finish: [200, {}, []],
      write: nil).tap do |resp|
      allow(resp).to receive(:[]=) { |k, v| resp.headers[k] = v }
      allow(resp).to receive(:[]) { |k| resp.headers[k] }
      allow(resp).to receive(:header).and_return(resp.headers)
      allow(resp).to receive(:body=)
    end
  end
end

# Shared context for view specs with mocked request/session/customer
RSpec.shared_context "view_test_context" do
  let(:rack_request) do
    env = {
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_HOST' => 'example.com',
      'rack.session' => {},
      'ots.locale' => 'en'
    }

    # Create a properly configured double that responds to env access
    request = instance_double('Rack::Request')
    allow(request).to receive(:env).and_return(env)
    allow(request).to receive(:nil?).and_return(false)
    # Allow accessing env with hash notation (important for locale extraction)
    allow(request).to receive(:[]) { |key| env[key] }
    request
  end

  let(:config) do
    {
      locales: ['en'],
      site: {
        host: 'test.domain.com',
        secret_options: {
          default_ttl: 86_400,
          ttl_options: [3600, 86_400]
        },
        authentication: {
          enabled: true,
          signup: true
        }
      },
      development: {
        enabled: false,
        frontend_host: ''
      }
    }
  end

  let(:session) do
    instance_double('V1::Session',
      authenticated?: true,
      add_shrimp: 'test_shrimp',
      get_messages: [])
  end

  let(:customer) do
    instance_double('V1::Customer',
      custid: 'test@example.com',
      email: 'test@example.com',
      anonymous?: false,
      planid: 'basic',
      created: Time.now.to_i,
      safe_dump: {
        'identifier' => 'test@example.com',
        'role' => 'customer'
      })
  end

  before(:each) do
    # Ensure OT.conf returns the configured test values
    allow(OT).to receive(:conf).and_return(config)

    # Add global mocks needed for most tests
    allow(OT).to receive(:d9s_enabled).and_return(false)
    allow(Onetime).to receive(:with_diagnostics).and_yield

    allow(OT).to receive(:locales).and_return({
      'en' => {
        web: {
          COMMON: {
            description: 'Test Description',
            keywords: 'test,keywords'
          }
        }
      }
    })
  end
end
