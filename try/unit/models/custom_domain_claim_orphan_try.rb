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

## Create a domain normally
@domain_name = "orphan-#{@timestamp}.example.com"
@domain = Onetime::CustomDomain.create!(@domain_name, @dummy_org.objid)
@domain.display_domain
#=> @domain_name

## Domain initially belongs to dummy_org
@domain.org_id
#=> @dummy_org.objid

## Orphan step 1: Remove from org's domains ZSET
@dummy_org.remove_domain(@domain)
@dummy_org.domain?(@domain)
#=> false

## Orphan step 2: Clear org_id field directly in Redis
Familia.dbclient.hdel(@domain.dbkey, 'org_id')
@domain = Onetime::CustomDomain.load_by_display_domain(@domain_name)
@domain.org_id.to_s.empty?
#=> true

## Orphan step 3: Clear from owners hash
Onetime::CustomDomain.owners.remove(@domain.to_s)
Onetime::CustomDomain.owners.get(@domain.to_s).nil?
#=> true

## Verify domain is recognized as orphaned
Onetime::CustomDomain.orphaned?(@domain_name)
#=> true

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

# TC-DIV-005: Display domain dual-index consistency after orphan claim.
# After claim_orphaned_domain, both display_domains (manual) and
# display_domain_index (auto) should still map correctly to this domain.

## TC-DIV-005: display_domains (manual) maps to claimed domain after orphan claim
Onetime::CustomDomain.display_domains.get(@domain_name) == @claimed.identifier
#=> true

## TC-DIV-005: display_domain_index (auto) maps to claimed domain after orphan claim
Onetime::CustomDomain.display_domain_index.get(@domain_name).nil?
#=> false

## TC-DIV-005: load_by_display_domain finds the claimed domain
@lookup = Onetime::CustomDomain.load_by_display_domain(@domain_name)
@lookup.org_id == @claiming_org.objid
#=> true

# Teardown
@claimed.destroy! if @claimed&.exists?
@claiming_org.destroy! if @claiming_org&.exists?
@dummy_org.destroy! if @dummy_org&.exists?
@owner2.destroy! if @owner2&.exists?
@owner1.destroy! if @owner1&.exists?
