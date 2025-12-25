# apps/web/billing/spec/support/shared_contexts/with_authenticated_customer.rb
#
# frozen_string_literal: true

# Shared context for authenticated customer with session
#
# Purpose: Reduce duplication in controller specs that require authenticated users.
# Sets up a customer with valid session and cleanup.
#
# Usage:
#   RSpec.describe 'BillingController' do
#     include Rack::Test::Methods
#     include_context 'with_authenticated_customer'
#
#     it 'allows authenticated access' do
#       get '/billing/api/plans'
#       expect(last_response.status).to eq(200)
#     end
#   end
#
# Provides:
#   - customer: Authenticated Onetime::Customer instance
#   - Sets rack.session with authentication
#   - Automatic cleanup in after hook
#
RSpec.shared_context 'with_authenticated_customer' do
  let(:created_customers) { [] }

  let(:customer) do
    cust = Onetime::Customer.create!(email: "test-#{SecureRandom.hex(4)}@example.com")
    created_customers << cust
    cust
  end

  before do
    customer.save

    # Mock authentication by setting up session
    env 'rack.session', {
      'authenticated' => true,
      'external_id' => customer.extid,
    }
  end

  after do
    # Clean up created customers
    created_customers.each(&:destroy!)
  end

  # Helper: Create additional customer (non-authenticated)
  #
  # Useful for testing authorization failures (wrong customer accessing resources)
  #
  # @param email [String] Optional custom email
  # @return [Onetime::Customer]
  def create_other_customer(email: nil)
    email ||= "other-#{SecureRandom.hex(4)}@example.com"
    cust = Onetime::Customer.create!(email: email)
    created_customers << cust
    cust.save
    cust
  end

  # Helper: Switch session to different customer
  #
  # @param other_customer [Onetime::Customer] Customer to authenticate as
  def authenticate_as(other_customer)
    env 'rack.session', {
      'authenticated' => true,
      'external_id' => other_customer.extid,
    }
  end

  # Helper: Clear authentication session
  def clear_authentication
    env 'rack.session', {}
  end
end
