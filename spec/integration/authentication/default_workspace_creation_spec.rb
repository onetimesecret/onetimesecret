# Generated rspec code for default_workspace_creation
# Updated: 2025-12-07

require 'spec_helper'

RSpec.describe 'default_workspace_creation_try', order: :defined do
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
    require_relative '../../../apps/web/auth/operations/create_default_workspace'

    # Create first test customer
    @email = generate_unique_test_email("workspace_new")
    @customer = Onetime::Customer.create!(email: @email)

    # Create default workspace for first customer
    @result = Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call
    @org = @result[:organization]
    @team = @result[:team]

    # Test idempotency
    @result2 = Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call

    # Test skipping for existing customer (using nil to test nil handling)
    @existing_customer = nil
    @result3 = Auth::Operations::CreateDefaultWorkspace.new(customer: @existing_customer).call

    # Create second customer for registration flow test
    @registration_email = "fullflow_#{SecureRandom.hex(8)}_#{Familia.now.to_i}@example.com"
    @new_customer = Onetime::Customer.create!(email: @registration_email)

    # Capture initial org count before creating workspace
    @new_customer_initial_org_count = @new_customer.organization_instances.count

    # Create workspace for new customer
    @workspace = Auth::Operations::CreateDefaultWorkspace.new(customer: @new_customer).call
  end

  it 'Customer created successfully' do
    expect(@customer.class).to eq(Onetime::Customer)
  end

  it 'CreateDefaultWorkspace operation creates org and team' do
    expect(@result.class).to eq(Hash)
    expect(@result.keys.sort).to eq([:organization, :team])
  end

  it 'Organization was created with correct owner' do
    expect(@org.class).to eq(Onetime::Organization)
    expect(@org.owner_id).to eq(@customer.custid)
  end

  it 'Organization has default name' do
    expect(@org.display_name).to eq("Default Organization")
  end

  it 'Organization contact email matches customer email' do
    expect(@org.contact_email).to eq(@customer.email)
  end

  it 'Customer is automatically added as org member' do
    expect(@org.member?(@customer)).to eq(true)
  end

  it 'Team was created with correct owner' do
    expect(@team.class).to eq(Onetime::Team)
    expect(@team.owner_id).to eq(@customer.custid)
  end

  it 'Team has default name' do
    expect(@team.display_name).to eq("Default Team")
  end

  it 'Team is linked to the organization' do
    expect(@team.org_id).to eq(@org.objid)
  end

  it 'Customer is automatically added as team member' do
    expect(@team.member?(@customer)).to eq(true)
  end

  it 'Running CreateDefaultWorkspace again does nothing (idempotent)' do
    expect(@result2).to eq(nil)
  end

  it 'Customer is member of exactly one organization' do
    customer_orgs = @customer.organization_instances.to_a
    expect(customer_orgs.size).to eq(1)
  end

  it 'CreateDefaultWorkspace skips if customer is nil' do
    expect(@result3).to eq(nil)
  end

  it 'Create new customer for registration flow test' do
    expect(@new_customer.class).to eq(Onetime::Customer)
    expect(@new_customer_initial_org_count).to eq(0)
  end

  it 'Create workspace for new registration' do
    expect(@workspace.class).to eq(Hash)
    expect(@workspace).not_to be_nil
  end

  it 'Workspace contains org and team' do
    expect(@workspace[:organization].class).to eq(Onetime::Organization)
    expect(@workspace[:team].class).to eq(Onetime::Team)
  end

  it 'New customer is member of the created org' do
    expect(@workspace[:organization].members.member?(@new_customer.objid)).to eq(true)
  end

  it 'New customer is member of the created team' do
    expect(@workspace[:team].members.member?(@new_customer.objid)).to eq(true)
  end
end
