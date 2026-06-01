# try/unit/models/custom_domain_owners_destroy_proof_try.rb
#
# frozen_string_literal: true
#
# Proof: CustomDomain#destroy! removes the entry from the `owners`
# class_hashkey via the explicit `self.class.owners.remove(to_s)` call.

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb

@timestamp = Familia.now.to_i
@owner     = Onetime::Customer.create!(email: "owner_proof_#{@timestamp}@test.com")
@org       = Onetime::Organization.create!("Proof Org #{@timestamp}", @owner, "proof-#{@timestamp}@test.com")
@domain    = Onetime::CustomDomain.create!("proof-#{@timestamp}.example.com", @org.objid)
@key       = @domain.to_s

## owners hash has the entry after create!, mapped to the org objid
Onetime::CustomDomain.owners.get(@key)
#=> @org.objid

## owners HKEYS contains the domain key (direct Redis read, not via instances)
Familia.dbclient.hkeys(Onetime::CustomDomain.owners.dbkey).include?(@key)
#=> true

## destroy! removes the entry from the owners class_hashkey
@domain.destroy!
Onetime::CustomDomain.owners.get(@key)
#=> nil

## Direct Redis HKEYS no longer lists the domain key
Familia.dbclient.hkeys(Onetime::CustomDomain.owners.dbkey).include?(@key)
#=> false

# Teardown
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
