# try/unit/models/v2/custom_domain_extid_try.rb
#
# frozen_string_literal: true

# DOM-VAL-033: ExtID lookup consistency after CRUD operations
#
# Verifies that HGET custom_domain:extid_lookup {extid} returns the
# correct objid after create, and that the entry is removed after
# destroy. ExtID lookup powers API routes — stale entries cause 404s,
# missing entries block access.

require_relative '../../../support/test_helpers'

OT.boot! :test, false

Familia.dbclient.flushdb

@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "extid_test_#{@timestamp}@test.com")
@org = Onetime::Organization.create!("ExtID Test Org", @owner, "extid@test.com")

## CustomDomain class has extid_lookup class hashkey
Onetime::CustomDomain.respond_to?(:extid_lookup)
#=> true

## Create a custom domain
@domain = Onetime::CustomDomain.create!("extid-test.example.com", @org.objid)
@domain.class
#=> Onetime::CustomDomain

## Domain has an extid
@domain.extid
#=~> /^cd[0-9a-z]+$/

## Domain has an objid
@domain.objid
#=~> /^[0-9a-f-]+$/

## ExtID lookup returns correct objid after create
Onetime::CustomDomain.extid_lookup.get(@domain.extid)
#=> @domain.objid

## find_by_extid returns the correct domain after create
found = Onetime::CustomDomain.find_by_extid(@domain.extid)
found.objid
#=> @domain.objid

## find_by_extid returns correct display_domain
found = Onetime::CustomDomain.find_by_extid(@domain.extid)
found.display_domain
#=> "extid-test.example.com"

## Create second domain and verify its extid lookup
@domain2 = Onetime::CustomDomain.create!("extid-test2.example.com", @org.objid)
Onetime::CustomDomain.extid_lookup.get(@domain2.extid)
#=> @domain2.objid

## First domain extid still resolves correctly after second create
Onetime::CustomDomain.extid_lookup.get(@domain.extid)
#=> @domain.objid

## Destroy domain and verify extid lookup is cleared
@saved_extid = @domain.extid
@saved_objid = @domain.objid
@domain.destroy!
Onetime::CustomDomain.extid_lookup.get(@saved_extid)
#=> nil

## find_by_extid returns nil for destroyed domain
Onetime::CustomDomain.find_by_extid(@saved_extid)
#=> nil

## Second domain extid still works after first is destroyed
Onetime::CustomDomain.find_by_extid(@domain2.extid).objid
#=> @domain2.objid

## Destroyed domain object hash no longer exists in Redis
Familia.dbclient.exists("custom_domain:#{@saved_objid}:object")
#=> 0

# Teardown
@domain2.destroy! if @domain2&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
