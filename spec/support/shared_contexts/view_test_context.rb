# spec/support/shared_contexts/view_test_context.rb
#
# frozen_string_literal: true

# Shared context for view specs with mocked request/session/customer.
# Provides common test doubles for view rendering tests.
#
# Usage:
#   RSpec.describe 'View rendering' do
#     include_context 'view_test_context'
#
#     it 'renders with customer data' do
#       expect(customer.email).to eq('test@example.com')
#     end
#   end
#
RSpec.shared_context 'view_test_context' do
  let(:rack_request) do
    env = {
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_HOST' => 'example.com',
      'rack.session' => {},
      'ots.locale' => 'en'
    }

    request = instance_double('Rack::Request')
    allow(request).to receive(:env).and_return(env)
    allow(request).to receive(:nil?).and_return(false)
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
    allow(OT).to receive(:conf).and_return(config)
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
