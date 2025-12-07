# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/auth/default_workspace_creation_try.rb
# Updated: 2025-12-06 19:02:09 -0800

require 'spec_helper'

RSpec.describe 'default_workspace_creation_try' do
  before(:all) do
    require 'securerandom'
    begin
      OT.boot! :test, false unless OT.ready?
    rescue Redis::CannotConnectError, Redis::ConnectionError => e
      puts "SKIP: Requires Redis connection (#{e.class})"
      exit 0
    end
    require_relative '../../../apps/web/auth/operations/create_default_workspace'
    @email = generate_unique_test_email("workspace_new")
    @customer = Onetime::Customer.create!(email: @email)
  end

  it 'Customer created successfully' do
    result = begin
      @customer.class
    end
    expect(result).to eq(Onetime::Customer)
  end

  it 'CreateDefaultWorkspace operation creates org and team' do
    result = begin
      @result = Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call
      [@result.class, @result.keys.sort]
    end
    expect(result).to eq([Hash, [:organization, :team]])
  end

  it 'Organization was created with correct owner' do
    result = begin
      @org = @result[:organization]
      [@org.class, @org.owner_id]
    end
    expect(result).to eq([Onetime::Organization, @customer.custid])
  end

  it 'Organization has default name' do
    result = begin
      @org.display_name
    end
    expect(result).to eq("Default Organization")
  end

  it 'Organization contact email matches customer email' do
    result = begin
      @org.contact_email
    end
    expect(result).to eq(@customer.email)
  end

  it 'Customer is automatically added as org member' do
    result = begin
      @org.member?(@customer)
    end
    expect(result).to eq(true)
  end

  it 'Team was created with correct owner' do
    result = begin
      @team = @result[:team]
      [@team.class, @team.owner_id]
    end
    expect(result).to eq([Onetime::Team, @customer.custid])
  end

  it 'Team has default name' do
    result = begin
      @team.display_name
    end
    expect(result).to eq("Default Team")
  end

  it 'Team is linked to the organization' do
    result = begin
      @team.org_id
    end
    expect(result).to eq(@org.objid)
  end

  it 'Customer is automatically added as team member' do
    result = begin
      @team.member?(@customer)
    end
    expect(result).to eq(true)
  end

  it 'Running CreateDefaultWorkspace again does nothing (idempotent)' do
    result = begin
      @result2 = Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call
      @result2
    end
    expect(result).to eq(nil)
  end

  it 'Customer is member of exactly one organization' do
    result = begin
      customer_orgs = @customer.organization_instances.to_a
      customer_orgs.size
    end
    expect(result).to eq(1)
  end

  it 'CreateDefaultWorkspace skips if customer already has org' do
    result = begin
      @result3 = Auth::Operations::CreateDefaultWorkspace.new(customer: @existing_customer).call
      @result3
    end
    expect(result).to eq(nil)
  end

  it 'Create new customer for registration flow test' do
    result = begin
      @registration_email = "fullflow_#{SecureRandom.hex(8)}_#{Familia.now.to_i}@example.com"
      @new_customer = Onetime::Customer.create!(email: @registration_email)
      [@new_customer.class, @new_customer.organization_instances.count]
    end
    expect(result).to eq([Onetime::Customer, 0])
  end

  it 'Create workspace for new registration' do
    result = begin
      @workspace = Auth::Operations::CreateDefaultWorkspace.new(customer: @new_customer).call
      workspace_created = !@workspace.nil?
      [@workspace.class, workspace_created]
    end
    expect(result).to eq([Hash, true])
  end

  it 'Workspace contains org and team' do
    result = begin
      [@workspace[:organization].class, @workspace[:team].class]
    end
    expect(result).to eq([Onetime::Organization, Onetime::Team])
  end

  it 'New customer is member of the created org' do
    result = begin
      @workspace[:organization].members.member?(@new_customer.objid)
    end
    expect(result).to eq(true)
  end

  it 'New customer is member of the created team' do
    result = begin
      @workspace[:team].members.member?(@new_customer.objid)
    end
    expect(result).to eq(true)
  end

end
