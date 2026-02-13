# try/unit/models/custom_domain_instances_owners_try.rb
#
# frozen_string_literal: true

# DOM-VAL-030: Verifies that custom_domain:instances (SortedSet) and
# custom_domain:owners (HashKey) maintain bidirectional integrity after
# create, claim_orphaned_domain, and destroy operations.
#
# Invariant: ZRANGE custom_domain:instances and HKEYS custom_domain:owners
# must produce identical sets at all times.

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

@timestamp = Familia.now.to_i
@owner1 = Onetime::Customer.create!(email: "io_owner1_#{@timestamp}@test.com")
@owner2 = Onetime::Customer.create!(email: "io_owner2_#{@timestamp}@test.com")
@org1 = Onetime::Organization.create!("IO Test Org1 #{@timestamp}", @owner1, "io-org1-#{@timestamp}@test.com")
@org2 = Onetime::Organization.create!("IO Test Org2 #{@timestamp}", @owner2, "io-org2-#{@timestamp}@test.com")

## Baseline: instances and owners are both empty
@instances_set = Onetime::CustomDomain.instances.members.to_set
@owners_keys = Onetime::CustomDomain.owners.keys.to_set
@instances_set == @owners_keys
#=> true

## After creating first domain, instances and owners stay in sync
@domain1 = Onetime::CustomDomain.create!("sync-one-#{@timestamp}.example.com", @org1.objid)
@instances_set = Onetime::CustomDomain.instances.members.to_set
@owners_keys = Onetime::CustomDomain.owners.keys.to_set
@instances_set == @owners_keys
#=> true

## After creating second domain, still in sync
@domain2 = Onetime::CustomDomain.create!("sync-two-#{@timestamp}.example.com", @org1.objid)
@instances_set = Onetime::CustomDomain.instances.members.to_set
@owners_keys = Onetime::CustomDomain.owners.keys.to_set
[@instances_set == @owners_keys, @instances_set.size]
#=> [true, 2]

## After creating third domain in different org, still in sync
@domain3 = Onetime::CustomDomain.create!("sync-three-#{@timestamp}.example.com", @org2.objid)
@instances_set = Onetime::CustomDomain.instances.members.to_set
@owners_keys = Onetime::CustomDomain.owners.keys.to_set
[@instances_set == @owners_keys, @instances_set.size]
#=> [true, 3]

## Owners hash maps each domain to correct org_id
@owners_correct = [
  Onetime::CustomDomain.owners.get(@domain1.to_s) == @org1.objid,
  Onetime::CustomDomain.owners.get(@domain2.to_s) == @org1.objid,
  Onetime::CustomDomain.owners.get(@domain3.to_s) == @org2.objid,
]
@owners_correct
#=> [true, true, true]

## Orphan a domain and reclaim it: instances/owners remain in sync
# Orphan domain2 by clearing its org_id directly in Redis
@domain2.remove_from_organization_domains(@org1)
Familia.dbclient.hdel(@domain2.dbkey, 'org_id')
Onetime::CustomDomain.owners.remove(@domain2.to_s)
# At this point, instances has domain2 but owners does NOT — temporary inconsistency
@pre_claim_instances = Onetime::CustomDomain.instances.members.to_set
@pre_claim_owners = Onetime::CustomDomain.owners.keys.to_set
@pre_claim_instances == @pre_claim_owners
#=> false

## After claiming orphaned domain, sync is restored
@claimed = Onetime::CustomDomain.create!("sync-two-#{@timestamp}.example.com", @org2.objid)
@instances_set = Onetime::CustomDomain.instances.members.to_set
@owners_keys = Onetime::CustomDomain.owners.keys.to_set
[@instances_set == @owners_keys, @instances_set.size]
#=> [true, 3]

## Claimed domain now points to org2 in owners hash
Onetime::CustomDomain.owners.get(@claimed.to_s)
#=> @org2.objid

## After destroying a domain, instances and owners stay in sync
@domain1.destroy!
@instances_set = Onetime::CustomDomain.instances.members.to_set
@owners_keys = Onetime::CustomDomain.owners.keys.to_set
[@instances_set == @owners_keys, @instances_set.size]
#=> [true, 2]

## Destroying all remaining domains: both empty again
@claimed.destroy!
@domain3.destroy!
@instances_set = Onetime::CustomDomain.instances.members.to_set
@owners_keys = Onetime::CustomDomain.owners.keys.to_set
[@instances_set == @owners_keys, @instances_set.size]
#=> [true, 0]

# Teardown
@org2.destroy! if @org2&.exists?
@org1.destroy! if @org1&.exists?
@owner2.destroy! if @owner2&.exists?
@owner1.destroy! if @owner1&.exists?
