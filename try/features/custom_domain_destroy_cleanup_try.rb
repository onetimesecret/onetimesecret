# try/features/custom_domain_destroy_cleanup_try.rb
#
# frozen_string_literal: true

# Stage 5b regression anchor: CustomDomain#destroy! cleans every class-level
# structure that holds a reference to the destroyed record.
#
# Current cleanup chain (as of this commit):
#   CustomDomain#destroy! (lib/onetime/models/custom_domain.rb:402)
#     -> self.class.rem(self) (lib/onetime/models/custom_domain.rb:989)
#          -> instances.remove
#          -> display_domains.remove         (manual class_hashkey)
#          -> owners.remove                  (manual class_hashkey)
#          -> fobj.remove_from_all_indexes   (iterates indexing_relationships,
#                                             dispatches remove_from_class_*_index)
#     -> super -> ExternalIdentifier#destroy! (clears extid_lookup)
#           -> Horreum::Persistence#destroy! (clears main key, related_fields,
#                                             instances)
#
# These tests lock that behavior in. They will fail if a future refactor
# drops any of these cleanups.

require_relative '../../try/support/test_helpers'

OT.boot! :test, false

Familia.dbclient.flushdb

@timestamp = Familia.now.to_i
@owner_a = Onetime::Customer.create!(email: "dcu_a_#{@timestamp}@test.com")
@org_a   = Onetime::Organization.create!("DCU Org A", @owner_a, "dcu_a@test.com")
@owner_b = Onetime::Customer.create!(email: "dcu_b_#{@timestamp}@test.com")
@org_b   = Onetime::Organization.create!("DCU Org B", @owner_b, "dcu_b@test.com")

# --------------------------------------------------------------------------
# Scenario 1: Full-field create -> destroy, all class-level structures clean.
# --------------------------------------------------------------------------

## S1: Create a domain under org A
@dom_1 = Onetime::CustomDomain.create!("cleanup.example.com", @org_a.objid)
@s1_display = @dom_1.display_domain
@s1_objid   = @dom_1.objid
@s1_extid   = @dom_1.extid
[@s1_display, @s1_objid.to_s.empty?, @s1_extid.to_s.empty?]
#=> ["cleanup.example.com", false, false]

## S1: Before destroy, the record is present in every structure
[
  Onetime::CustomDomain.display_domain_index.get(@s1_display).nil?,
  Onetime::CustomDomain.display_domains.get(@s1_display).nil?,
  Onetime::CustomDomain.owners.get(@s1_objid).nil?,
  Onetime::CustomDomain.instances.member?(@s1_objid),
  Onetime::CustomDomain.extid_lookup.get(@s1_extid).nil?,
]
#=> [false, false, false, true, false]

## S1: Destroy removes the record from all five structures
@dom_1.destroy!
[
  Onetime::CustomDomain.display_domain_index.get(@s1_display),
  Onetime::CustomDomain.display_domains.get(@s1_display),
  Onetime::CustomDomain.owners.get(@s1_objid),
  Onetime::CustomDomain.instances.member?(@s1_objid),
  Onetime::CustomDomain.extid_lookup.get(@s1_extid),
]
#=> [nil, nil, nil, false, nil]

## S1: Main object hash is gone from Redis
Familia.dbclient.exists("custom_domain:#{@s1_objid}:object")
#=> 0

## S1: Destroyed record is also removed from its org's participates_in set
@org_a.domains.member?(@s1_objid)
#=> false

# --------------------------------------------------------------------------
# Scenario 2: Destroy + re-create same FQDN under different org succeeds.
# --------------------------------------------------------------------------

## S2: First create under org A
@s2_fqdn = "reuse.example.com"
@dom_2a  = Onetime::CustomDomain.create!(@s2_fqdn, @org_a.objid)
@dom_2a.display_domain
#=> "reuse.example.com"

## S2: Destroy leaves no residual index entries for the FQDN
@s2_a_objid = @dom_2a.objid
@dom_2a.destroy!
[
  Onetime::CustomDomain.display_domain_index.get(@s2_fqdn),
  Onetime::CustomDomain.display_domains.get(@s2_fqdn),
  @org_a.domains.member?(@s2_a_objid),
]
#=> [nil, nil, false]

## S2: Re-create same FQDN under org B succeeds without RecordExistsError
@dom_2b = Onetime::CustomDomain.create!(@s2_fqdn, @org_b.objid)
[@dom_2b.display_domain, @dom_2b.org_id]
#=> ["reuse.example.com", @org_b.objid]

## S2: Recreated record has a fresh identifier
@dom_2b.objid != @dom_2a.objid
#=> true

## S2: Recreated record is present in display_domain_index
Onetime::CustomDomain.display_domain_index.get(@s2_fqdn).nil?
#=> false

# --------------------------------------------------------------------------
# Scenario 3: Destroy on a record with empty display_domain must not raise.
# Seed the corrupt state directly in Redis, bypassing save() validation.
# --------------------------------------------------------------------------

## S3: Seed a record with empty display_domain directly via HSET
@s3_objid = "broken-#{@timestamp}"
Familia.dbclient.hset("custom_domain:#{@s3_objid}:object",
                      "objid", @s3_objid,
                      "org_id", @org_a.objid,
                      "display_domain", "")
Onetime::CustomDomain.instances.add(@s3_objid)
Onetime::CustomDomain.owners.put(@s3_objid, @org_a.objid)
Familia.dbclient.exists("custom_domain:#{@s3_objid}:object")
#=> 1

## S3: Load the corrupt record; display_domain is empty
@s3_broken = Onetime::CustomDomain.find_by_identifier(@s3_objid)
@s3_broken.display_domain.to_s
#=> ""

## S3: destroy! completes without raising
@s3_result = begin
  @s3_broken.destroy!
  "ok"
rescue StandardError => ex
  "raised: #{ex.class}: #{ex.message}"
end
@s3_result
#=> "ok"

## S3: instances and owners (keyed on objid) are cleaned
[
  Onetime::CustomDomain.instances.member?(@s3_objid),
  Onetime::CustomDomain.owners.get(@s3_objid),
]
#=> [false, nil]

## S3: Main object hash is deleted
Familia.dbclient.exists("custom_domain:#{@s3_objid}:object")
#=> 0

# --------------------------------------------------------------------------
# Scenario 4: Double-destroy is idempotent. Second call must not raise.
# --------------------------------------------------------------------------

## S4: Create, destroy once, then destroy again
@dom_4 = Onetime::CustomDomain.create!("double.example.com", @org_a.objid)
@dom_4.destroy!
@s4_result = begin
  @dom_4.destroy!
  "ok"
rescue StandardError => ex
  "raised: #{ex.class}: #{ex.message}"
end
@s4_result
#=> "ok"

## S4: Indexes remain clean after the second destroy
[
  Onetime::CustomDomain.display_domain_index.get("double.example.com"),
  Onetime::CustomDomain.display_domains.get("double.example.com"),
]
#=> [nil, nil]

# Teardown
Familia.dbclient.flushdb
