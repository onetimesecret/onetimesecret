# apps/web/auth/spec/integration/full/internal_request_hook_proof_spec.rb
#
# frozen_string_literal: true

# Proof: Does Rodauth's internal_request(:create_account) call after_create_account?
#
# Run:
#   source .env.test && AUTHENTICATION_MODE=full bundle exec rspec \
#     apps/web/auth/spec/integration/full/internal_request_hook_proof_spec.rb

require_relative '../../spec_helper'

RSpec.describe 'Proof: internal_request hook invocation', type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.auth_config.reload! if Onetime.respond_to?(:auth_config) && Onetime.auth_config.respond_to?(:reload!)
    Onetime::Application::Registry.reset! if Onetime::Application::Registry.respond_to?(:reset!)

    Onetime.boot!(:test, force: true)
    Onetime::Application::Registry.prepare_application_registry
  end

  before do
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured'
    end
  end

  let(:test_suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:test_email) { "proof_#{test_suffix}@example.com" }
  let(:password) { 'TestPassword123!' }

  after do
    Auth::Database.connection[:accounts].where(email: test_email).delete rescue nil
    Onetime::Customer.find_by_email(test_email)&.destroy! rescue nil
  end

  it 'confirms after_create_account hook IS called by internal_request' do
    # Precondition: Auth::Config is set up correctly
    expect(Auth::Config).to respond_to(:create_account)
    expect(Auth::Config.private_method_defined?(:after_create_account)).to be(true)

    # Act: create account via internal_request
    puts "\n[PROOF] Calling Auth::Config.create_account(login: #{test_email}, ...)"
    Auth::Config.create_account(
      login: test_email,
      password: password
    )

    # Check SQL: account should exist
    account = Auth::Database.connection[:accounts].where(email: test_email).first
    puts "[PROOF] SQL account exists: #{!account.nil?}"
    puts "[PROOF] SQL account row: #{account.inspect}" if account
    expect(account).not_to be_nil, "Account should be created in SQL"

    # Check Redis: Customer should exist because hook runs
    customer = Onetime::Customer.find_by_email(test_email)
    puts "[PROOF] Redis customer exists: #{!customer.nil?}"
    puts "[PROOF] Redis customer: #{customer.inspect}" if customer

    # After the hook-collision fix (#3275), the after_create_account hook chain
    # runs correctly. account.rb's hook creates the Customer, then calls
    # billing.rb's add_billing_redirect_to_response (if billing enabled).
    # Previously, billing.rb's hook overwrote account.rb's, so Customer was
    # never created via internal_request.
    if customer.nil?
      puts "\n[PROOF] ❌ after_create_account hook was NOT called"
      puts "[PROOF]    Account exists in SQL but Customer missing from Redis."
      puts "[PROOF]    Hook collision bug may have regressed."
    else
      puts "\n[PROOF] ✅ after_create_account hook WAS called"
    end

    expect(customer).not_to be_nil, <<~MSG
      Customer should exist in Redis after create_account.
      The after_create_account hook (account.rb) creates Customer records.
      If this fails, check for hook collision: another hook file may be
      overwriting account.rb's after_create_account definition.
    MSG
  end
end
