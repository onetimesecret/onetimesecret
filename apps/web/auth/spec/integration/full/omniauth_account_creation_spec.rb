# apps/web/auth/spec/integration/omniauth_account_creation_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Tests the after_omniauth_create_account hook operations that create Customer
# and Organization records for new SSO users.
#
# Operations tested:
#   - Auth::Operations::CreateCustomer
#   - Auth::Operations::CreateDefaultWorkspace
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/omniauth_account_creation_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'after_omniauth_create_account operations', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require_relative '../../../operations/create_customer'
    require_relative '../../../operations/create_default_workspace'
  end

  # Track created resources for cleanup
  let(:created_customers) { [] }
  let(:created_organizations) { [] }
  let(:created_account_ids) { [] }

  after do
    # Clean up test data
    created_organizations.each do |org|
      org.delete! if org&.exists?
    rescue StandardError => e
      # Non-fatal cleanup error
    end

    created_customers.each do |customer|
      customer.delete! if customer&.exists?
    rescue StandardError => e
      # Non-fatal cleanup error
    end

    created_account_ids.each do |account_id|
      Auth::Database.connection[:accounts].where(id: account_id).delete
    rescue StandardError => e
      # Non-fatal cleanup error
    end
  end

  # Helper to generate unique test emails
  def unique_test_email(prefix = 'test')
    "#{prefix}-#{SecureRandom.hex(8)}@integration-test.example.com"
  end

  # Helper to create a test account in the database
  def create_test_account(email:)
    db = Auth::Database.connection
    account_id = db[:accounts].insert(
      email: email,
      status_id: 1, # verified status
      created_at: Time.now,
      updated_at: Time.now
    )
    created_account_ids << account_id
    { id: account_id, email: email }
  end

  describe 'CreateCustomer operation' do
    it 'creates a Customer in Redis with correct attributes' do
      email = unique_test_email('create-customer')
      account = create_test_account(email: email)

      # Verify no Customer exists yet
      expect(Onetime::Customer.exists?(email)).to be false

      # Call the operation
      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account
      )
      customer = operation.call
      created_customers << customer

      # Verify Customer was created
      expect(customer).to be_a(Onetime::Customer)
      expect(customer.email).to eq(email)
      expect(customer.role.to_s).to eq('customer')
      expect(customer.verified.to_s).to eq('false')
      expect(customer.custid).not_to be_nil
      expect(customer.extid).not_to be_nil
    end

    it 'links customer extid to rodauth account via external_id' do
      email = unique_test_email('link-extid')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account
      )
      customer = operation.call
      created_customers << customer

      # Verify external_id was set in the accounts table
      db = Auth::Database.connection
      stored_extid = db[:accounts].where(id: account[:id]).get(:external_id)

      expect(stored_extid).to eq(customer.extid)
      expect(stored_extid).not_to be_nil
    end

    it 'finds existing Customer via find_by_email when email matches' do
      email = unique_test_email('existing-customer')
      account = create_test_account(email: email)

      # First call creates the customer
      operation1 = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account
      )
      customer1 = operation1.call
      created_customers << customer1

      # Verify Customer.find_by_email works (used by operation's exists? check)
      found = Onetime::Customer.find_by_email(email)
      expect(found).not_to be_nil
      expect(found.custid).to eq(customer1.custid)
    end

    # Regression guard for the immutability rule documented on CreateCustomer:
    # signup_domain_id and provisioning_origin are set only when the customer
    # is first created and must not be rewritten on subsequent SSO logins.
    # Before PR #3237 the omniauth callback overwrote signup_domain_id after
    # every SSO login via a custom domain; the fix moved the assignment into
    # the initial create! and relies on the existing-customer branch being a
    # no-op for these fields. If that guard is reverted, this spec fails.
    it 'preserves signup_domain_id on subsequent calls for an existing customer' do
      email = unique_test_email('signup-domain-immutable')
      account = create_test_account(email: email)
      original_domain_id = "domain-original-#{SecureRandom.hex(4)}"
      different_domain_id = "domain-different-#{SecureRandom.hex(4)}"

      # First call: customer is created with the original signup_domain_id
      customer1 = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        signup_domain_id: original_domain_id,
      ).call
      created_customers << customer1
      expect(customer1.signup_domain_id).to eq(original_domain_id)

      # Second call: same email, different signup_domain_id (simulates a
      # subsequent SSO login arriving via a different custom domain).
      customer2 = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        signup_domain_id: different_domain_id,
      ).call

      # Same customer record, original signup_domain_id intact.
      expect(customer2.custid).to eq(customer1.custid)
      expect(customer2.signup_domain_id).to eq(original_domain_id)

      # Reload from Redis to confirm nothing was persisted under the new value.
      reloaded = Onetime::Customer.load(customer1.custid)
      expect(reloaded.signup_domain_id).to eq(original_domain_id)
    end

    it 'preserves provisioning_origin on subsequent calls for an existing customer' do
      email = unique_test_email('provisioning-origin-immutable')
      account = create_test_account(email: email)

      # First call seeds the customer as an SSO JIT signup.
      customer1 = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        provisioning_origin: 'sso_jit',
      ).call
      created_customers << customer1
      expect(customer1.provisioning_origin).to eq('sso_jit')

      # A later call must not relabel the provisioning origin.
      customer2 = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account,
        provisioning_origin: 'canonical_signup',
      ).call

      expect(customer2.custid).to eq(customer1.custid)
      expect(customer2.provisioning_origin).to eq('sso_jit')

      reloaded = Onetime::Customer.load(customer1.custid)
      expect(reloaded.provisioning_origin).to eq('sso_jit')
    end

    it 'sets default role to customer (not admin or colonel)' do
      email = unique_test_email('default-role')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account
      )
      customer = operation.call
      created_customers << customer

      expect(customer.role.to_s).to eq('customer')
      expect(customer.role.to_s).not_to eq('admin')
      expect(customer.role.to_s).not_to eq('colonel')
    end

    it 'sets verified to false (requires separate verification flow)' do
      email = unique_test_email('verified-false')
      account = create_test_account(email: email)

      operation = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account
      )
      customer = operation.call
      created_customers << customer

      expect(customer.verified.to_s).to eq('false')
    end
  end

  describe 'CreateDefaultWorkspace operation' do
    it 'creates Organization with is_default true' do
      email = unique_test_email('workspace-default')
      customer = Onetime::Customer.create!(
        email: email,
        role: 'customer',
        verified: true
      )
      created_customers << customer

      # Verify no organizations exist
      expect(customer.organization_instances.count).to eq(0)

      # Call the operation
      operation = Auth::Operations::CreateDefaultWorkspace.new(customer: customer)
      result = operation.call
      org = result[:organization]
      created_organizations << org

      expect(org).to be_a(Onetime::Organization)
      expect(org.is_default).to be true
    end

    it 'is idempotent - does not create duplicate organizations' do
      email = unique_test_email('workspace-idempotent')
      customer = Onetime::Customer.create!(
        email: email,
        role: 'customer',
        verified: true
      )
      created_customers << customer

      # First call - creates organization
      operation1 = Auth::Operations::CreateDefaultWorkspace.new(customer: customer)
      result1 = operation1.call
      created_organizations << result1[:organization]

      expect(customer.organization_instances.count).to eq(1)

      # Second call - should be no-op
      operation2 = Auth::Operations::CreateDefaultWorkspace.new(customer: customer)
      result2 = operation2.call

      expect(result2).to be_nil # Returns nil when workspace exists
      expect(customer.organization_instances.count).to eq(1)
    end

    it 'returns nil when customer is nil' do
      operation = Auth::Operations::CreateDefaultWorkspace.new(customer: nil)
      result = operation.call

      expect(result).to be_nil
    end

    it 'customer has organization after workspace creation' do
      email = unique_test_email('workspace-customer-link')
      customer = Onetime::Customer.create!(
        email: email,
        role: 'customer',
        verified: true
      )
      created_customers << customer

      expect(customer.organization_instances).to be_empty

      operation = Auth::Operations::CreateDefaultWorkspace.new(customer: customer)
      result = operation.call
      org = result[:organization]
      created_organizations << org

      # Customer should now have the organization
      expect(customer.organization_instances).not_to be_empty
      expect(customer.organization_instances.first.objid).to eq(org.objid)
    end
  end

  describe 'full account creation flow' do
    it 'CreateCustomer followed by CreateDefaultWorkspace creates linked records' do
      email = unique_test_email('full-flow')
      account = create_test_account(email: email)

      # Step 1: Create Customer
      customer_op = Auth::Operations::CreateCustomer.new(
        account_id: account[:id],
        account: account
      )
      customer = customer_op.call
      created_customers << customer

      # Step 2: Create Workspace
      workspace_op = Auth::Operations::CreateDefaultWorkspace.new(customer: customer)
      result = workspace_op.call
      org = result[:organization]
      created_organizations << org

      # Verify the full chain
      db = Auth::Database.connection
      stored_extid = db[:accounts].where(id: account[:id]).get(:external_id)

      # Account -> Customer link via external_id
      expect(stored_extid).to eq(customer.extid)

      # Customer -> Organization link
      expect(customer.organization_instances.count).to eq(1)
      expect(customer.organization_instances.first.is_default).to be true

      # All records have correct email
      expect(customer.email).to eq(email)
    end
  end
end
