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
# The BaseView constructor expects a single Rack::Request argument and extracts
# session/customer from req.env['otto.strategy_result']. This context provides:
#   - rack_request: A mock Rack::Request with strategy_result in env
#   - strategy_result: Mock Otto auth result containing session and user
#   - session: Mock session object
#   - customer: Mock customer object
#
RSpec.shared_context 'view_test_context' do
  let(:config) do
    {
      'locales' => ['en'],
      'site' => {
        'host' => 'test.domain.com',
        'secret_options' => {
          'default_ttl' => 86_400,
          'ttl_options' => [3600, 86_400]
        },
        'authentication' => {
          'enabled' => true,
          'signup' => true
        }
      },
      'development' => {
        'enabled' => false,
        'frontend_host' => ''
      }
    }
  end

  # Session is a Hash (rack session data), not an object with methods.
  # The authenticated? method lives on strategy_result, not the session.
  let(:session) do
    {
      'csrf' => 'test_shrimp',
      'account_id' => 'test@example.com',
      'email' => 'test@example.com',
      'awaiting_mfa' => false
    }
  end

  let(:customer) do
    cust = instance_double('Onetime::Customer',
      custid: 'test@example.com',
      email: 'test@example.com',
      anonymous?: false,
      planid: 'basic',
      created: Time.now.to_i,
      safe_dump: {
        'identifier' => 'test@example.com',
        'custid' => 'test@example.com',
        'role' => 'customer',
        'verified' => true,
        'last_login' => nil,
        'locale' => 'en',
        'updated' => nil,
        'created' => Time.now.to_i,
        'stripe_customer_id' => nil,
        'stripe_subscription_id' => nil,
        'stripe_checkout_email' => nil,
        'secrets_created' => '0',
        'secrets_burned' => '0',
        'secrets_shared' => '0',
        'emails_sent' => '0',
        'active' => true
      })
    allow(cust).to receive(:role?).and_return(false)
    cust
  end

  # Mock Otto StrategyResult - this is what BaseView extracts from req.env
  let(:strategy_result) do
    instance_double('Otto::Security::Authentication::StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {})
  end

  let(:rack_request) do
    env = {
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_HOST' => 'example.com',
      'rack.session' => session,
      'otto.locale' => 'en',
      'otto.strategy_result' => strategy_result,
      'onetime.nonce' => nil
    }

    request = instance_double('Rack::Request')
    allow(request).to receive(:env).and_return(env)
    allow(request).to receive(:nil?).and_return(false)
    allow(request).to receive(:session).and_return(session)
    request
  end

  before(:each) do
    allow(OT).to receive(:conf).and_return(config)
    allow(OT).to receive(:d9s_enabled).and_return(false)
    allow(OT).to receive(:default_locale).and_return('en')
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

    # Mock I18n for view initialization
    allow(I18n).to receive(:available_locales).and_return([:en, :fr_CA, :fr_FR])
    allow(I18n).to receive(:default_locale).and_return(:en)
    allow(I18n).to receive(:t).with('web.COMMON.description', anything).and_return('Test Description')
    allow(I18n).to receive(:t).with('web.COMMON.keywords', anything).and_return('test,keywords')
  end
end
