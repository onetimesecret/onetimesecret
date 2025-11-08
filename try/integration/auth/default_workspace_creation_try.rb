## Auth::Operations::CreateDefaultWorkspace - Default Workspace Creation

require 'securerandom'
require_relative '../../support/test_helpers'

begin
  OT.boot! :test, false unless OT.ready?
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

# Load the operation class
require_relative '../../../apps/web/auth/operations/create_default_workspace'

# Setup: Create a new customer (simulating registration)
@email = "newuser_#{Familia.now.to_i}@example.com"
@customer = Onetime::Customer.create!(email: @email)

## Customer created successfully
@customer.class
#=> Onetime::Customer

## CreateDefaultWorkspace operation creates org and team
@result = Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call
[@result.class, @result.keys.sort]
#=> [Hash, [:organization, :team]]

## Organization was created with correct owner
@org = @result[:organization]
[@org.class, @org.owner_id]
#=> [Onetime::Organization, @customer.custid]

## Organization has default name
@org.display_name
#=> "Default Organization"

## Organization contact email matches customer email
@org.contact_email
#=> @customer.email

## Customer is automatically added as org member
@org.member?(@customer)
#=> true

## Team was created with correct owner
@team = @result[:team]
[@team.class, @team.owner_id]
#=> [Onetime::Team, @customer.custid]

## Team has default name
@team.display_name
#=> "Default Team"

## Team is linked to the organization
@team.org_id
#=> @org.orgid

## Customer is automatically added as team member
@team.member?(@customer)
#=> true

## Running CreateDefaultWorkspace again does nothing (idempotent)
@result2 = Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call
@result2
#=> nil

## Customer is member of exactly one organization
all_orgs = Onetime::Organization.values.to_a.map { |id| Onetime::Organization.load(id) }.compact
customer_orgs = all_orgs.select { |org| org.members.member?(@customer.objid) }
customer_orgs.size
#=> 1

## Customer already in org scenario
@existing_email = "existing_#{Familia.now.to_i}@example.com"
@existing_customer = Onetime::Customer.create!(email: @existing_email)
@existing_org = Onetime::Organization.create!("Existing Org", @existing_customer, @existing_email)

## CreateDefaultWorkspace skips if customer already has org
@result3 = Auth::Operations::CreateDefaultWorkspace.new(customer: @existing_customer).call
@result3
#=> nil

## Verify full registration flow integration
# This simulates what happens when a new user registers
@registration_email = "fullflow_#{Familia.now.to_i}@example.com"
@new_customer = Onetime::Customer.create!(email: @registration_email)

## Create workspace for new registration
@workspace = Auth::Operations::CreateDefaultWorkspace.new(customer: @new_customer).call
workspace_created = !@workspace.nil?
[@workspace.class, workspace_created]
#=> [Hash, true]

## Workspace contains org and team
[@workspace[:organization].class, @workspace[:team].class]
#=> [Onetime::Organization, Onetime::Team]

## New customer is member of the created org
@workspace[:organization].members.member?(@new_customer.objid)
#=> true

## New customer is member of the created team
@workspace[:team].members.member?(@new_customer.objid)
#=> true
