# tests/unit/ruby/rspec/support/view_context.rb

RSpec.shared_context "view_test_context" do
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
    instance_double('Session',
      authenticated?: true,
      add_shrimp: 'test_shrimp',
      get_messages: [])
  end

  let(:customer) do
    instance_double('Customer',
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


  before do
    allow(OT).to receive(:conf).and_return(config)
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
