# apps/web/billing/spec/support/shared_contexts/with_authenticated_customer.rb
#
# frozen_string_literal: true

require 'digest'
require 'securerandom'

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

  # Generate a valid CSRF token compatible with Rack::Protection::AuthenticityToken
  # The token must be URL-safe base64 encoded (32 bytes = 43 chars without padding)
  let(:csrf_token) { SecureRandom.urlsafe_base64(32, padding: false) }

  # Generate deterministic email based on test description for VCR cassette matching
  def deterministic_email(prefix = 'test')
    test_hash = Digest::SHA256.hexdigest(RSpec.current_example.full_description)[0..7]
    "#{prefix}-#{test_hash}@example.com"
  end

  let(:customer) do
    cust = Onetime::Customer.create!(email: deterministic_email)
    created_customers << cust
    cust
  end

  before do
    customer.save

    # Mock authentication by setting up session with CSRF token
    # Rack::Protection::AuthenticityToken stores the raw token in session[:csrf]
    # and validates X-CSRF-Token header against it (supports both masked and unmasked)
    env 'rack.session', {
      'authenticated' => true,
      'external_id' => customer.extid,
      :csrf => csrf_token,
    }

    # Add CSRF header to all requests (matches frontend Axios interceptor)
    # Using unmasked token here - Rack::Protection accepts raw token via compare_with_real_token
    header 'X-CSRF-Token', csrf_token
  end

  # Helper: Include CSRF token header in requests
  #
  # @return [Hash] Headers hash with CSRF token
  def csrf_headers
    { 'HTTP_X_CSRF_TOKEN' => csrf_token }
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
    email ||= deterministic_email('other')
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
      :csrf => csrf_token,
    }
  end

  # Helper: Clear authentication session while preserving CSRF token
  #
  # Preserves the CSRF token so POST requests pass CSRF validation
  # but fail authentication (expected 401 response).
  def clear_authentication
    env 'rack.session', { :csrf => csrf_token }
  end
end
