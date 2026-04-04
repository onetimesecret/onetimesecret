# spec/integration/all/lazy_organization_creation_spec.rb
#
# frozen_string_literal: true

# Integration tests for lazy organization creation flow
#
# Issue #2880: Remove write operations from OrganizationLoader auth phase
#
# Tests the complete flow:
# 1. Auth succeeds with nil org (user has no orgs)
# 2. When entitlement-gated action is attempted, lazy creation triggers
# 3. CreateDefaultWorkspace is called
# 4. Federation check runs (apply_pending_federation!)
#
# Run: bundle exec rspec spec/integration/all/lazy_organization_creation_spec.rb

require 'spec_helper'

RSpec.describe 'Lazy Organization Creation', type: :integration, order: :defined, shared_db_state: true do
  before(:all) do
    require 'securerandom'
    # Clear Redis env vars to ensure test config defaults are used (port 2121)
    ENV.delete('REDIS_URL')
    ENV.delete('VALKEY_URL')
    begin
      OT.boot! :test, false unless OT.ready?
    rescue Redis::CannotConnectError, Redis::ConnectionError => e
      puts "SKIP: Requires Redis connection (#{e.class})"
      exit 0
    end

    # Load required operations
    require_relative '../../../apps/web/auth/operations/create_default_workspace'
    require_relative '../../../apps/web/billing/models/pending_federated_subscription'

    # Create customer WITHOUT organizations
    @test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
    @email = "lazy_creation_#{@test_suffix}@onetimesecret.com"
    @customer = Onetime::Customer.create!(email: @email)
  end

  after(:all) do
    # Clean up test data
    @customer&.organization_instances&.to_a&.each do |org|
      org.destroy! if org&.exists?
    end
    @customer&.destroy! if @customer&.exists?
  end

  describe 'Customer without organizations' do
    it 'starts with no organizations' do
      expect(@customer.organization_instances.count).to eq(0)
    end
  end

  describe 'CreateDefaultWorkspace operation' do
    before(:all) do
      # Trigger lazy creation
      @workspace_result = Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call
      @created_org = @workspace_result[:organization] if @workspace_result
    end

    it 'creates an organization for customer without orgs' do
      expect(@workspace_result).not_to be_nil
      expect(@workspace_result[:organization]).to be_a(Onetime::Organization)
    end

    it 'creates org with Default Workspace name' do
      expect(@created_org.display_name).to eq('Default Workspace')
    end

    it 'sets customer email as contact_email' do
      expect(@created_org.contact_email).to eq(@email)
    end

    it 'sets customer as owner' do
      expect(@created_org.owner_id).to eq(@customer.custid)
    end

    it 'adds customer as member' do
      expect(@created_org.member?(@customer)).to be true
    end

    it 'marks organization as default workspace' do
      expect(@created_org.is_default).to be_truthy
    end

    it 'customer now has exactly one organization' do
      expect(@customer.organization_instances.count).to eq(1)
    end
  end

  describe 'Idempotency' do
    before(:all) do
      @second_result = Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call
    end

    it 'returns nil when organization already exists' do
      expect(@second_result).to be_nil
    end

    it 'does not create duplicate organization' do
      expect(@customer.organization_instances.count).to eq(1)
    end
  end

  describe 'Nil customer handling' do
    it 'returns nil when customer is nil' do
      result = Auth::Operations::CreateDefaultWorkspace.new(customer: nil).call
      expect(result).to be_nil
    end
  end
end

RSpec.describe 'Federation Application on Workspace Creation', type: :integration, order: :defined, shared_db_state: true do
  before(:all) do
    require 'securerandom'
    ENV.delete('REDIS_URL')
    ENV.delete('VALKEY_URL')
    begin
      OT.boot! :test, false unless OT.ready?
    rescue Redis::CannotConnectError, Redis::ConnectionError => e
      puts "SKIP: Requires Redis connection (#{e.class})"
      exit 0
    end

    require_relative '../../../apps/web/auth/operations/create_default_workspace'
    require_relative '../../../apps/web/billing/models/pending_federated_subscription'

    # Set up federation secret for email hash computation
    @original_federation_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'test-federation-secret-for-lazy-creation-12345'

    # Create a new customer
    @test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
    @email = "federated_#{@test_suffix}@onetimesecret.com"
    @customer = Onetime::Customer.create!(email: @email)

    # Pre-compute email hash for the pending subscription
    @email_hash = Onetime::Utils::EmailHash.compute(@email) rescue nil
  end

  after(:all) do
    # Clean up
    @customer&.organization_instances&.to_a&.each do |org|
      org.destroy! if org&.exists?
    end
    @customer&.destroy! if @customer&.exists?
    ENV['FEDERATION_SECRET'] = @original_federation_secret
  end

  describe 'when no pending federation exists' do
    before(:all) do
      @result = Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call
      @org = @result[:organization]
    end

    after(:all) do
      @org&.destroy! if @org&.exists?
    end

    it 'creates organization without federation' do
      expect(@org).to be_a(Onetime::Organization)
    end

    it 'organization is not marked as federated' do
      expect(@org.subscription_federated?).to be false
    end

    it 'organization has nil or empty subscription_status' do
      expect(@org.subscription_status.to_s).to be_empty
    end
  end

  # Note: Testing with actual pending federated subscription would require
  # more complex setup with Billing::PendingFederatedSubscription model.
  # The apply_pending_federation! method is tested in organization_federation_try.rb
end

RSpec.describe 'Billing Webhook Organization Creation Paths', type: :integration, order: :defined, shared_db_state: true do
  before(:all) do
    require 'securerandom'
    ENV.delete('REDIS_URL')
    ENV.delete('VALKEY_URL')
    begin
      OT.boot! :test, false unless OT.ready?
    rescue Redis::CannotConnectError, Redis::ConnectionError => e
      puts "SKIP: Requires Redis connection (#{e.class})"
      exit 0
    end
  end

  # These tests verify that billing webhook handlers create organizations
  # using the canonical Organization.create! method with proper parameters.
  # Full webhook handler testing requires Stripe mocking which is in separate specs.

  describe 'Organization.create! canonical usage' do
    before(:all) do
      @test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
      @owner_email = "billing_owner_#{@test_suffix}@onetimesecret.com"
      @owner = Onetime::Customer.create!(email: @owner_email)
    end

    after(:all) do
      @owner&.organization_instances&.to_a&.each do |org|
        org.destroy! if org&.exists?
      end
      @owner&.destroy! if @owner&.exists?
    end

    it 'creates organization with is_default: true for billing flows' do
      org = Onetime::Organization.create!(
        "#{@owner.email}'s Workspace",
        @owner,
        @owner.email,
        is_default: true
      )
      expect(org.is_default).to be_truthy
      org.destroy!
    end

    it 'rejects duplicate contact_email' do
      first_org = Onetime::Organization.create!(
        'First Billing Org',
        @owner,
        "billing_unique_#{@test_suffix}@example.com",
        is_default: true
      )

      owner2 = Onetime::Customer.create!(email: "billing_owner2_#{@test_suffix}@onetimesecret.com")

      expect {
        Onetime::Organization.create!(
          'Second Billing Org',
          owner2,
          "billing_unique_#{@test_suffix}@example.com",
          is_default: true
        )
      }.to raise_error(Onetime::Problem, 'Organization exists for that email address')

      first_org.destroy!
      owner2.destroy!
    end

    it 'allows nil contact_email for orgs that will set billing_email later' do
      org = Onetime::Organization.create!(
        'Billing Org No Email',
        @owner,
        nil,
        is_default: true
      )
      expect(org.contact_email).to be_nil
      org.destroy!
    end
  end
end

RSpec.describe 'OrganizationContext in Logic Classes', type: :integration, order: :defined, shared_db_state: true do
  before(:all) do
    require 'securerandom'
    ENV.delete('REDIS_URL')
    ENV.delete('VALKEY_URL')
    begin
      OT.boot! :test, false unless OT.ready?
    rescue Redis::CannotConnectError, Redis::ConnectionError => e
      puts "SKIP: Requires Redis connection (#{e.class})"
      exit 0
    end

    require 'onetime/logic/organization_context'
  end

  describe 'OrganizationContext module' do
    let(:test_class) do
      Class.new do
        include Onetime::Logic::OrganizationContext
        attr_accessor :strategy_result, :cust

        def initialize(strategy_result, customer = nil)
          @strategy_result = strategy_result
          @cust = customer  # auth_org uses cust for lazy creation
          extract_organization_context(strategy_result)
        end
      end
    end

    context 'when strategy_result has organization_context' do
      let(:mock_org) { double('Organization', objid: 'org_test_123') }
      let(:strategy_result) do
        double(
          'StrategyResult',
          metadata: {
            organization_context: {
              organization: mock_org,
              organization_id: 'org_test_123',
              expires_at: Time.now.to_i + 300
            }
          }
        )
      end

      it 'extracts organization from metadata' do
        instance = test_class.new(strategy_result)
        expect(instance.organization).to eq(mock_org)
      end

      it 'auth_org returns organization from strategy_result' do
        instance = test_class.new(strategy_result)
        expect(instance.auth_org).to eq(mock_org)
      end
    end

    context 'when strategy_result has nil organization' do
      let(:strategy_result) do
        double(
          'StrategyResult',
          metadata: {
            organization_context: {
              organization: nil,
              organization_id: nil,
              expires_at: Time.now.to_i + 300
            }
          }
        )
      end

      it 'extracts nil organization from metadata' do
        instance = test_class.new(strategy_result)
        expect(instance.organization).to be_nil
      end

      it 'auth_org returns nil' do
        instance = test_class.new(strategy_result)
        expect(instance.auth_org).to be_nil
      end

      it 'require_organization! raises when organization is nil' do
        instance = test_class.new(strategy_result)
        expect { instance.require_organization! }.to raise_error(Onetime::Problem, 'No organization context')
      end
    end

    context 'when strategy_result is nil' do
      it 'handles nil strategy_result gracefully' do
        instance = test_class.new(nil)
        expect(instance.organization).to be_nil
      end
    end

    context 'lazy creation via auth_org with real customer' do
      before(:all) do
        @test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
        @lazy_email = "lazy_auth_org_#{@test_suffix}@onetimesecret.com"
        @lazy_customer = Onetime::Customer.create!(email: @lazy_email)
      end

      after(:all) do
        @lazy_customer&.organization_instances&.to_a&.each do |org|
          org.destroy! if org&.exists?
        end
        @lazy_customer&.destroy! if @lazy_customer&.exists?
      end

      it 'lazy-creates organization when cust exists but org is nil' do
        # Strategy result with nil organization (simulates auth without org)
        strategy_result = double(
          'StrategyResult',
          metadata: {
            organization_context: {
              organization: nil,
              organization_id: nil,
              expires_at: Time.now.to_i + 300
            }
          }
        )
        allow(strategy_result.metadata[:organization_context]).to receive(:[]=)

        instance = test_class.new(strategy_result, @lazy_customer)
        expect(@lazy_customer.organization_instances.count).to eq(0)

        # auth_org should trigger lazy creation
        org = instance.auth_org

        expect(org).to be_a(Onetime::Organization)
        expect(org.owner_id).to eq(@lazy_customer.custid)
        expect(@lazy_customer.organization_instances.count).to eq(1)
      end

      it 'does not create duplicate org on subsequent auth_org calls' do
        # After the previous test, customer should have one org
        # Create fresh strategy result pointing to nil (simulating new request)
        strategy_result = double(
          'StrategyResult',
          metadata: {
            organization_context: {
              organization: nil,
              organization_id: nil,
              expires_at: Time.now.to_i + 300
            }
          }
        )
        allow(strategy_result.metadata[:organization_context]).to receive(:[]=)

        instance = test_class.new(strategy_result, @lazy_customer)
        initial_count = @lazy_customer.organization_instances.count

        # This should return existing org (CreateDefaultWorkspace is idempotent)
        org = instance.auth_org

        # Note: The current implementation creates a new org because it checks
        # strategy_result.metadata which is nil, not the customer's actual orgs.
        # This is actually testing the real behavior - if we want idempotency,
        # CreateDefaultWorkspace handles it internally.
        expect(@lazy_customer.organization_instances.count).to eq(initial_count)
      end
    end
  end
end
