# try/unit/models/custom_domain_rename_index_try.rb
#
# frozen_string_literal: true

# TC-CON-003: Tests that update_display_domain properly maintains both
# display_domains (manual class_hashkey) and display_domain_index (auto
# unique_index) when the FQDN changes. Verifies no phantom entries remain.

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "rename_owner_#{@timestamp}@test.com")
@org = Onetime::Organization.create!("Rename Test Org #{@timestamp}", @owner, "rename-#{@timestamp}@test.com")

## Create a domain with initial display_domain
@old_name = "old-name-#{@timestamp}.example.com"
@domain = Onetime::CustomDomain.create!(@old_name, @org.objid)
@domain.display_domain
#=> @old_name

## Old name is in the manual display_domains index
Onetime::CustomDomain.display_domains.get(@old_name).nil?
#=> false

## Old name is findable via load_by_display_domain
Onetime::CustomDomain.load_by_display_domain(@old_name).nil?
#=> false

## Rename the domain using update_display_domain
@new_name = "new-name-#{@timestamp}.example.com"
@domain.update_display_domain(@new_name)
@domain.display_domain
#=> @new_name

## Old name is removed from manual display_domains index
Onetime::CustomDomain.display_domains.get(@old_name).nil?
#=> true

## New name is in the manual display_domains index
Onetime::CustomDomain.display_domains.get(@new_name)
#=> @domain.identifier

## New name is findable via load_by_display_domain
@loaded = Onetime::CustomDomain.load_by_display_domain(@new_name)
@loaded.display_domain
#=> @new_name

## Old name is NOT findable via load_by_display_domain (no phantom)
Onetime::CustomDomain.load_by_display_domain(@old_name).nil?
#=> true

## New name resolves via auto unique_index (find_by_display_domain)
@found = Onetime::CustomDomain.find_by_display_domain(@new_name)
@found.nil?
#=> false

## Old name does NOT resolve via auto unique_index (no phantom)
Onetime::CustomDomain.find_by_display_domain(@old_name).nil?
#=> true

## Attempting to rename to an existing domain raises error
@domain2 = Onetime::CustomDomain.create!("taken-#{@timestamp}.example.com", @org.objid)
begin
  @domain.update_display_domain("taken-#{@timestamp}.example.com")
  "unexpected_success"
rescue Onetime::Problem => e
  e.message
end
#=> "Domain already registered"

## Original domain still has the new name after failed rename
@domain.display_domain
#=> @new_name

# Teardown
@domain2.destroy! if @domain2&.exists?
@domain.destroy! if @domain&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
