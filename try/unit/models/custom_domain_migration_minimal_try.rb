# try/unit/models/custom_domain_migration_minimal_try.rb
#
# frozen_string_literal: true

# Minimal test to debug the setup issue

require_relative '../../support/test_models'

OT.boot! :test

# Ensure clean state
Familia.dbclient.flushdb if ENV['ENV'] == 'test'

puts "Creating customer..."
@test_id = SecureRandom.hex(4)
@cust = Onetime::Customer.create!(email: "test_#{@test_id}@test.com")
puts "Customer created with custid: #{@cust.custid}"

puts "Creating organization..."
@org = Onetime::Organization.create!("Test Org #{@test_id}", @cust, "billing_#{@test_id}@test.com")
puts "Organization created with extid: #{@org.objid}"

puts "Creating custom domain..."
@domain_name = "test#{@test_id}.example.com"
@domain = Onetime::CustomDomain.create!(@domain_name, @org.objid)
puts "Domain created: #{@domain.display_domain}"

## Customer exists
@cust.nil?
#=> false

## Customer has custid
@cust.custid.nil?
#=> false

## Organization exists
@org.nil?
#=> false

## Domain exists
@domain.nil?
#=> false

Familia.dbclient.flushdb if ENV['ENV'] == 'test'
