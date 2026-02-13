# try/unit/models/custom_domain_claim_orphan_try.rb
#
# frozen_string_literal: true

# Tests that claim_orphaned_domain updates all three locations:
#   C - organization:*:domains ZSET (via add_to_organization_domains)
#   D - custom_domain:*:object org_id field
#   E - custom_domain:owners hash (via owners.put)

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

@timestamp = Familia.now.to_i
@owner1 = Onetime::Customer.create!(email: "orphan_owner1_#{@timestamp}@test.com")
@owner2 = Onetime::Customer.create!(email: "orphan_owner2_#{@timestamp}@test.com")
@dummy_org = Onetime::Organization.create!("Dummy Org #{@timestamp}", @owner1, "dummy-#{@timestamp}@test.com")
@claiming_org = Onetime::Organization.create!("Claiming Org #{@timestamp}", @owner2, "claiming-#{@timestamp}@test.com")

## Create a domain normally, then orphan it
@domain_name = "orphan-#{@timestamp}.example.com"
@domain = Onetime::CustomDomain.create!(@domain_name, @dummy_org.objid)
@domain.display_domain
#=> @domain_name

## Domain initially belongs to dummy_org
@domain.org_id
#=> @dummy_org.objid

## Orphan the domain: clear org_id, remove from org ZSET, clear owners hash
# Remove from org's domains ZSET via the org's remove_domain method
@dummy_org.remove_domain(@domain)
# Delete the org_id field from the Redis hash entirely
Familia.dbclient.hdel(@domain.dbkey, 'org_id')
# Remove from owners class hash via the rem class method logic
Onetime::CustomDomain.owners.remove(@domain.to_s)
# Reload to confirm orphaned state
@domain = Onetime::CustomDomain.load(@domain.identifier)
@domain.org_id.to_s.empty?
#=> true

## Verify domain is recognized as orphaned
Onetime::CustomDomain.orphaned?(@domain_name)
#=> true

## Verify owners hash has been cleared for this domain
Onetime::CustomDomain.owners.get(@domain.to_s).nil?
#=> true

## Verify dummy_org no longer has the domain in its ZSET
@dummy_org.domain?(@domain)
#=> false

## Claim the orphaned domain via create! (triggers claim_orphaned_domain internally)
@claimed = Onetime::CustomDomain.create!(@domain_name, @claiming_org.objid)
@claimed.display_domain
#=> @domain_name

## Location D: org_id field on the domain object matches the claiming org
@claimed.org_id
#=> @claiming_org.objid

## Location C: domain appears in the claiming organization's domains ZSET
@claiming_org.domain?(@claimed)
#=> true

## Location E: owners hash has the correct org_id for this domain
Onetime::CustomDomain.owners.get(@claimed.to_s)
#=> @claiming_org.objid

## All three locations are consistent
@org_id_from_field = @claimed.org_id
@org_id_from_owners = Onetime::CustomDomain.owners.get(@claimed.to_s)
@in_org_zset = @claiming_org.domain?(@claimed)
[@org_id_from_field == @claiming_org.objid, @org_id_from_owners == @claiming_org.objid, @in_org_zset]
#=> [true, true, true]

# Teardown
@claimed.destroy! if @claimed&.exists?
@claiming_org.destroy! if @claiming_org&.exists?
@dummy_org.destroy! if @dummy_org&.exists?
@owner2.destroy! if @owner2&.exists?
@owner1.destroy! if @owner1&.exists?
