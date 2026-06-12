# spec/integration/all/organization_v1_migration_created_by_spec.rb
#
# frozen_string_literal: true

# Integration tests verifying that the v1 customer migration path
# (Organization.create_from_v1_customer!) sets `created_by` in lock-step
# with `owner_id`, per ADR-012.
#
# create_from_v1_customer! routes through Organization.create! at
# lib/onetime/models/organization/features/migration_fields.rb:70, so the
# dual-write that create! performs should propagate transitively. This
# spec pins that contract so a future refactor that bypasses create! can't
# regress silently.
#
# Run: bundle exec rspec spec/integration/all/organization_v1_migration_created_by_spec.rb

require 'spec_helper'

# create_from_v1_customer! uses String#present? from ActiveSupport. The
# other integration specs in this directory pull this in transitively
# through apps/web require_relative chains; this spec exercises the
# migration path directly, so we need the extension loaded explicitly.
require 'active_support/core_ext/object/blank'

RSpec.describe 'Organization.create_from_v1_customer! created_by dual-write',
                type: :integration, order: :defined, shared_db_state: true do
  before(:all) do
    require 'securerandom'
    ENV.delete('REDIS_URL')
    ENV.delete('VALKEY_URL')

    # Standalone materialization happens inside Organization.create!, which
    # runs here in before(:all) -- BEFORE billing_isolation.rb's before(:each)
    # disable hook fires. So a prior spec (or env) leaving BILLING_ENABLED=true
    # would make create! treat the org as SaaS and skip materialization,
    # failing the standalone assertions below. Disable billing explicitly here
    # so this spec is self-contained rather than dependent on hook ordering.
    BillingTestHelpers.disable_billing!

    begin
      OT.boot! :test, false unless OT.ready?
    rescue Redis::CannotConnectError, Redis::ConnectionError => e
      puts "SKIP: Requires Redis connection (#{e.class})"
      exit 0
    end

    # Pulls in Billing::BillingService used by store_payment_link_info.
    require_relative '../../../apps/web/billing/lib/billing_service'

    @test_suffix = "#{Familia.now.to_i}_#{rand(10_000)}"
    @email       = "v1_migration_#{@test_suffix}@onetimesecret.com"
    @customer    = Onetime::Customer.create!(email: @email)

    # Minimal v1 payload — no Stripe fields, so the billing branch is
    # skipped. We only care that the org gets created with both audit
    # fields populated.
    @v1_data = { 'custid' => @email, 'planid' => 'free' }
    @org     = Onetime::Organization.create_from_v1_customer!(@customer, @v1_data)
  end

  after(:all) do
    @org&.destroy! if @org&.exists?
    @customer&.destroy! if @customer&.exists?
  end

  it 'creates an Organization' do
    expect(@org).to be_a(Onetime::Organization)
  end

  it 'sets owner_id to the customer custid' do
    expect(@org.owner_id).to eq(@customer.custid)
  end

  it 'sets created_by to the customer custid (ADR-012)' do
    expect(@org.created_by).to eq(@customer.custid)
  end

  it 'created_by equals owner_id (lock-step invariant)' do
    expect(@org.created_by).to eq(@org.owner_id)
  end

  it 'marks the org as default workspace' do
    expect(@org.is_default).to be_truthy
  end

  it 'safe_dump exposes both owner_id and created_by' do
    dump = @org.safe_dump
    expect(dump[:owner_id]).to eq(@customer.custid)
    expect(dump[:created_by]).to eq(@customer.custid)
    expect(dump[:created_by]).to eq(dump[:owner_id])
  end

  # ADR-012 §Standalone mode (Stage 2 Unit C): the v1 migration path
  # routes through Organization.create! at
  # lib/onetime/models/organization/features/migration_fields.rb:70, so the
  # create-time materialization that Unit C wired in must propagate
  # transitively. Pinning this invariant catches a future refactor that
  # bypasses create! and silently leaves migrated orgs unmaterialized.
  it 'marks the migrated org as materialized (transitively via create!)' do
    expect(@org.entitlements_materialized?).to be true
  end

  it 'materializes STANDALONE_ENTITLEMENTS on the migrated org' do
    expected = Onetime::Models::Features::WithPlanEntitlements::STANDALONE_ENTITLEMENTS
    expect(@org.materialized_entitlements.to_a.sort).to eq(expected.sort)
  end
end
