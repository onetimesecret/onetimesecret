# spec/integration/api/domains/homepage_secrets_entitlement_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Integration tests for homepage_secrets entitlement enforcement
# in UpdateDomainBrand logic.
#
# The UpdateDomainBrand logic class gates allow_public_homepage behind
# the 'homepage_secrets' entitlement. When a user sets allow_public_homepage=true,
# the org must have the homepage_secrets entitlement or EntitlementRequired is raised.
#
# This mirrors the pattern in spec/integration/api/v2/entitlement_enforcement_spec.rb.
#
RSpec.describe 'UpdateDomainBrand homepage_secrets entitlement', type: :integration, billing: true do
  # Helper to create a mock organization with specific entitlements
  def mock_organization(planid:, entitlements:)
    org = double('Organization', planid: planid, objid: "org_#{SecureRandom.hex(4)}")
    allow(org).to receive(:can?) do |entitlement|
      entitlements.include?(entitlement.to_s)
    end
    org
  end

  # Helper to create a mock customer
  def mock_customer(custid: 'test@example.com')
    customer = double('Customer', custid: custid, role: 'customer')
    allow(customer).to receive(:anonymous?).and_return(false)
    allow(customer).to receive(:verified?).and_return(true)
    allow(customer).to receive(:increment_field)
    customer
  end

  # Helper to create a mock session
  def mock_session
    session_data = {}
    session = double('Session')
    allow(session).to receive(:[]) { |key| session_data[key] }
    allow(session).to receive(:[]=) { |key, value| session_data[key] = value }
    allow(session).to receive(:delete) { |key| session_data.delete(key) }
    allow(session).to receive(:destroy!)
    session
  end

  # Helper to create a mock custom domain
  def mock_custom_domain
    brand = double('Brand')
    allow(brand).to receive(:[]=)
    allow(brand).to receive(:remove)

    domain = double('CustomDomain')
    allow(domain).to receive(:exists?).and_return(true)
    allow(domain).to receive(:owner?).and_return(true)
    allow(domain).to receive(:brand).and_return(brand)
    allow(domain).to receive(:brand_settings).and_return(
      Onetime::CustomDomain::BrandSettings.from_hash({})
    )
    allow(domain).to receive(:updated=)
    allow(domain).to receive(:save)
    domain
  end

  # Build a logic instance with the domain validation stubbed out,
  # so we can focus on entitlement enforcement.
  def create_brand_logic(params:, org:, customer: nil)
    customer ||= mock_customer
    session = mock_session

    strategy_result = double('StrategyResult')
    allow(strategy_result).to receive(:session).and_return(session)
    allow(strategy_result).to receive(:user).and_return(customer)
    allow(strategy_result).to receive(:metadata).and_return({ organization: org })

    logic = DomainsAPI::Logic::Domains::UpdateDomainBrand.new(strategy_result, params)

    allow(logic).to receive(:org).and_return(org)
    allow(logic).to receive(:cust).and_return(customer)
    allow(logic).to receive(:sess).and_return(session)

    # Stub domain validation — not under test here
    custom_domain = mock_custom_domain
    allow(logic).to receive(:validate_domain) do
      logic.instance_variable_set(:@custom_domain, custom_domain)
    end

    logic
  end

  before(:all) do
    require 'onetime'
    Onetime.boot! :test

    # Require the DomainsAPI logic classes
    require 'domains/logic/domains/update_domain_brand'

    BillingTestHelpers.populate_test_plans([
      {
        plan_id: 'basic_branding_only',
        name: 'Basic Branding',
        tier: 1,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets custom_branding],
        limits: {},
      },
      {
        plan_id: 'branding_with_homepage',
        name: 'Branding Plus Homepage',
        tier: 2,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets custom_branding homepage_secrets],
        limits: {},
      },
    ])
  end

  describe 'when org lacks homepage_secrets entitlement' do
    let(:org) do
      mock_organization(
        planid: 'basic_branding_only',
        entitlements: %w[create_secrets custom_branding]
      )
    end

    it 'raises EntitlementRequired when setting allow_public_homepage=true' do
      logic = create_brand_logic(
        params: { 'extid' => 'abc123', 'brand' => { 'allow_public_homepage' => 'true' } },
        org: org
      )
      logic.process_params

      expect {
        logic.raise_concerns
      }.to raise_error(Onetime::EntitlementRequired) do |error|
        expect(error.entitlement).to eq('homepage_secrets')
        expect(error.current_plan).to eq('basic_branding_only')
      end
    end

    it 'does not raise when allow_public_homepage is false' do
      logic = create_brand_logic(
        params: { 'extid' => 'abc123', 'brand' => { 'allow_public_homepage' => 'false' } },
        org: org
      )
      logic.process_params

      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'does not raise when allow_public_homepage is not provided' do
      logic = create_brand_logic(
        params: { 'extid' => 'abc123', 'brand' => { 'primary_color' => '#FF0000' } },
        org: org
      )
      logic.process_params

      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  describe 'when org has homepage_secrets entitlement' do
    let(:org) do
      mock_organization(
        planid: 'branding_with_homepage',
        entitlements: %w[create_secrets custom_branding homepage_secrets]
      )
    end

    it 'does not raise when setting allow_public_homepage=true' do
      logic = create_brand_logic(
        params: { 'extid' => 'abc123', 'brand' => { 'allow_public_homepage' => 'true' } },
        org: org
      )
      logic.process_params

      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'does not raise when setting allow_public_homepage with boolean true' do
      logic = create_brand_logic(
        params: { 'extid' => 'abc123', 'brand' => { 'allow_public_homepage' => true } },
        org: org
      )
      logic.process_params

      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  describe 'EntitlementRequired error details for homepage_secrets' do
    let(:org) do
      mock_organization(
        planid: 'basic_branding_only',
        entitlements: %w[create_secrets custom_branding]
      )
    end

    it 'includes entitlement name and plan info in error' do
      logic = create_brand_logic(
        params: { 'extid' => 'abc123', 'brand' => { 'allow_public_homepage' => 'true' } },
        org: org
      )
      logic.process_params

      begin
        logic.raise_concerns
      rescue Onetime::EntitlementRequired => e
        expect(e.entitlement).to eq('homepage_secrets')
        expect(e.current_plan).to eq('basic_branding_only')
        expect(e.message).to include('homepage secrets')
      end
    end

    it 'provides a serializable hash' do
      logic = create_brand_logic(
        params: { 'extid' => 'abc123', 'brand' => { 'allow_public_homepage' => 'true' } },
        org: org
      )
      logic.process_params

      begin
        logic.raise_concerns
      rescue Onetime::EntitlementRequired => e
        hash = e.to_h
        expect(hash[:entitlement]).to eq('homepage_secrets')
        expect(hash[:current_plan]).to eq('basic_branding_only')
      end
    end
  end
end
