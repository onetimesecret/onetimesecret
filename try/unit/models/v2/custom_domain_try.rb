# try/unit/models/v2/custom_domain_try.rb
#
# frozen_string_literal: true

# DOM-VAL-071: After CustomDomain.create!, verify all three data locations
# are consistent:
#   (D) custom_domain:{objid}:object has org_id field set
#   (C) organization:{org_id}:domains sorted set contains the domain
#   (E) custom_domain:owners hash maps domainid -> org_id
# Also verifies custom_domain:instances and custom_domain:display_domains entries.

require_relative '../../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "cdv_owner_#{@timestamp}@test.com")
@org = Onetime::Organization.create!("CDV Test Org", @owner, "cdv_#{@timestamp}@test.com")

## Create domain via CustomDomain.create!
@domain = Onetime::CustomDomain.create!("val-test.example.com", @org.objid)
@domain.class
#=> Onetime::CustomDomain

## (D) org_id field is set on the domain object
@domain.org_id
#=> @org.objid

## (D) org_id persists after reload from Redis
@reloaded = Onetime::CustomDomain.find_by_identifier(@domain.domainid)
@reloaded.org_id
#=> @org.objid

## (C) Domain appears in organization:{org_id}:domains sorted set
@org.domain?(@domain.domainid)
#=> true

## (C) Organization domains collection has exactly one entry
@org.domains.size
#=> 1

## (E) custom_domain:owners hash contains the domain entry
Onetime::CustomDomain.owners.get(@domain.domainid)
#=> @org.objid

## custom_domain:instances sorted set contains the domain
Onetime::CustomDomain.instances.member?(@domain.domainid)
#=> true

## custom_domain:display_domains hash maps fqdn to domainid
Onetime::CustomDomain.display_domains.get("val-test.example.com")
#=> @domain.domainid

## Create second domain and verify all locations
@domain2 = Onetime::CustomDomain.create!("api-val.example.com", @org.objid)
@domain2.org_id
#=> @org.objid

## (C) Organization now has two domains
@org.domains.size
#=> 2

## (E) Owners hash has entry for second domain
Onetime::CustomDomain.owners.get(@domain2.domainid)
#=> @org.objid

## Instances sorted set contains both domains
[Onetime::CustomDomain.instances.member?(@domain.domainid),
 Onetime::CustomDomain.instances.member?(@domain2.domainid)]
#=> [true, true]

## After destroy!, domain removed from all three locations
@destroyed_id = @domain2.domainid
@destroyed_display = @domain2.display_domain
@domain2.destroy!
@domain2_exists = @domain2.exists?
@domain2_exists
#=> false

## (D) Domain object no longer exists in Redis
Familia.dbclient.exists?("custom_domain:#{@destroyed_id}:object")
#=> false

## (C) Organization domains decremented
@org.domains.size
#=> 1

## (E) Owners hash no longer has entry for destroyed domain
Onetime::CustomDomain.owners.get(@destroyed_id).nil?
#=> true

## Instances sorted set no longer contains destroyed domain
Onetime::CustomDomain.instances.member?(@destroyed_id)
#=> false

## Display domains hash no longer maps destroyed domain
Onetime::CustomDomain.display_domains.get(@destroyed_display).nil?
#=> true

# Teardown
@domain.destroy! if @domain&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
