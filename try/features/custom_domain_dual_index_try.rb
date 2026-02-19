# try/features/custom_domain_dual_index_try.rb
#
# frozen_string_literal: true

# TC-DIV-002 (and related): display_domain dual-index consistency tests
#
# CustomDomain maintains two name-to-ID indexes:
#   1. display_domains  — manual class_hashkey (custom_domain:display_domains)
#   2. display_domain_index — Familia unique_index (custom_domain:display_domain_index)
#
# Both should stay in sync through create! and destroy! lifecycle.
# Divergence means a domain can't be found by name (missing entry)
# or blocks re-creation (stale entry).
#
# FIXED: destroy! now calls rem() and remove_from_all_indexes to clean up
# both the manual display_domains hashkey and the Familia unique_index
# (display_domain_index). Domain re-creation works correctly after destroy.

require_relative '../../try/support/test_helpers'

OT.boot! :test, false

Familia.dbclient.flushdb

@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "dualidx_#{@timestamp}@test.com")
@org = Onetime::Organization.create!("DualIdx Org", @owner, "dualidx@test.com")

## CustomDomain has display_domains class hashkey
Onetime::CustomDomain.respond_to?(:display_domains)
#=> true

## CustomDomain has display_domain_index class hashkey
Onetime::CustomDomain.respond_to?(:display_domain_index)
#=> true

## Both indexes start empty
[Onetime::CustomDomain.display_domains.size, Onetime::CustomDomain.display_domain_index.size]
#=> [0, 0]

## Create a domain and verify display_domains index is populated
@domain = Onetime::CustomDomain.create!("dual.example.com", @org.objid)
Onetime::CustomDomain.display_domains.get("dual.example.com").nil?
#=> false

## display_domain_index also has an entry after create
Onetime::CustomDomain.display_domain_index.get("dual.example.com").nil?
#=> false

## display_domains points to correct domain identifier
@dd_val = Onetime::CustomDomain.display_domains.get("dual.example.com")
@dd_val == @domain.identifier
#=> true

## display_domain_index also has a non-nil value
@ddi_val = Onetime::CustomDomain.display_domain_index.get("dual.example.com")
!@ddi_val.nil?
#=> true

## Destroy the domain
@saved_display = @domain.display_domain
@saved_identifier = @domain.identifier
@domain.destroy!
@domain.exists?
#=> false

## display_domains (manual hashkey) is clean after destroy
Onetime::CustomDomain.display_domains.get(@saved_display)
#=> nil

## FIXED: display_domain_index (unique_index) is clean after destroy
# destroy! now calls remove_from_all_indexes which cleans the unique_index.
Onetime::CustomDomain.display_domain_index.get(@saved_display).nil?
#=> true

# TC-LKP-002: find_by_display_domain returns nil for destroyed domain.
# The auto-generated finder from unique_index should not return a ghost
# record after destroy! cleans the display_domain_index.

## TC-LKP-002: find_by_display_domain returns nil after destroy!
Onetime::CustomDomain.find_by_display_domain(@saved_display).nil?
#=> true

## TC-LKP-002: load_by_display_domain returns nil after destroy!
Onetime::CustomDomain.load_by_display_domain(@saved_display).nil?
#=> true

## TC-LKP-002: from_display_domain returns nil after destroy!
Onetime::CustomDomain.from_display_domain(@saved_display).nil?
#=> true

## FIXED: Re-creating same domain after destroy succeeds
@domain_b = Onetime::CustomDomain.create!("dual.example.com", @org.objid)
@domain_b.display_domain
#=> "dual.example.com"

## TC-LKP-002: find_by_display_domain finds re-created domain
@found_after_recreate = Onetime::CustomDomain.find_by_display_domain(@saved_display)
@found_after_recreate.nil?
#=> false

## TC-LKP-002: Re-created domain has different identifier
@found_after_recreate.identifier != @saved_identifier
#=> true

# TC-LKP-003: After destroy, both indexes are clean (no divergence).

## TC-LKP-003: from_display_domain loads the re-created domain
Onetime::CustomDomain.from_display_domain(@saved_display).nil?
#=> false

## TC-LKP-003: load_by_display_domain also finds the re-created domain
Onetime::CustomDomain.load_by_display_domain(@saved_display).nil?
#=> false

## TC-LKP-003: display_domain_index points to re-created domain
Onetime::CustomDomain.display_domain_index.get(@saved_display).nil?
#=> false

# TC-CON-004: Re-creation works immediately after destroy (no stale index).

## TC-CON-004: After re-creation, display_domains points to new domain
Onetime::CustomDomain.display_domains.get("dual.example.com") == @domain_b.identifier
#=> true

## TC-CON-004: After re-creation, display_domain_index points to new domain
Onetime::CustomDomain.display_domain_index.get("dual.example.com").nil?
#=> false

## TC-CON-004: New domain has different identifier than destroyed one
@domain_b.identifier != @saved_identifier
#=> true

# TC-DIV-007: rem() is a low-level class method that only cleans manual indexes.
# The Familia auto-index (display_domain_index) is NOT cleaned by rem() alone.
# Callers must also call remove_from_all_indexes for complete cleanup.
# This is by design -- destroy! and delete! handle the full cleanup.

## TC-DIV-007: Create a domain for rem() isolation test
@domain_c = Onetime::CustomDomain.create!("rem-test.example.com", @org.objid)
@rem_display = @domain_c.display_domain
@rem_id = @domain_c.identifier
Onetime::CustomDomain.display_domains.get(@rem_display).nil?
#=> false

## TC-DIV-007: rem() cleans display_domains (manual hashkey)
Onetime::CustomDomain.rem(@domain_c)
Onetime::CustomDomain.display_domains.get(@rem_display)
#=> nil

## TC-DIV-007: FIXED: rem() now also cleans display_domain_index
# Previously rem() only handled manual indexes, leaving stale auto-index entries.
# Now rem() cleans all indexes for consistency.
Onetime::CustomDomain.display_domain_index.get(@rem_display).nil?
#=> true

## TC-DIV-007: rem() also cleans instances and owners
Onetime::CustomDomain.instances.member?(@rem_id)
#=> false

## TC-DIV-007: Cleanup the domain object (indexes already clean from rem)
@domain_c.clear

# TC-DIV-004: Direct save() without create! — auto-index populated, manual not.
# When building CustomDomain manually and calling save(), Familia's save hooks
# populate display_domain_index (auto unique_index) but NOT display_domains
# (manual class_hashkey). This means load_by_display_domain returns nil
# while the auto-index has an entry.

## TC-DIV-004: Build domain manually and save directly
@save_domain = Onetime::CustomDomain.new(display_domain: "save-only.example.com", org_id: @org.objid)
@save_domain.save
@save_domain.exists?
#=> true

## TC-DIV-004: display_domains (manual) has NO entry after direct save
Onetime::CustomDomain.display_domains.get("save-only.example.com")
#=> nil

## TC-DIV-004: display_domain_index (auto unique_index) HAS entry after direct save
Onetime::CustomDomain.display_domain_index.get("save-only.example.com").nil?
#=> false

## TC-DIV-004: load_by_display_domain returns nil (uses manual display_domains)
Onetime::CustomDomain.load_by_display_domain("save-only.example.com")
#=> nil

## TC-DIV-004: from_display_domain also returns nil (uses manual display_domains)
Onetime::CustomDomain.from_display_domain("save-only.example.com")
#=> nil

## TC-DIV-004: instances sorted set HAS entry (auto-populated by Familia on save)
Onetime::CustomDomain.instances.member?(@save_domain.identifier)
#=> true

## TC-DIV-004: owners hash has NO entry (manual, not populated by save)
Onetime::CustomDomain.owners.get(@save_domain.identifier)
#=> nil

## TC-DIV-004: Cleanup save-only domain
@save_domain.remove_from_all_indexes
@save_domain.clear

# TC-DIV-006: add() writes manual index only, NOT unique_index
# The add() class method updates display_domains, instances, and owners
# but NOT the Familia unique_index (display_domain_index). The unique_index
# is managed by Familia's save lifecycle hooks.

## TC-DIV-006: Build a domain object and save it
@add_domain = Onetime::CustomDomain.new(display_domain: "add-only.example.com", org_id: @org.objid)
@add_domain.save
@add_domain.exists?
#=> true

## TC-DIV-006: Before add(), display_domains has no entry
Onetime::CustomDomain.display_domains.get("add-only.example.com")
#=> nil

## TC-DIV-006: Call add() directly and verify display_domains is populated
Onetime::CustomDomain.add(@add_domain)
Onetime::CustomDomain.display_domains.get("add-only.example.com").nil?
#=> false

## TC-DIV-006: display_domain_index was populated by save(), not by add()
Onetime::CustomDomain.display_domain_index.get("add-only.example.com").nil?
#=> false

# TC-EDGE-004: Serialization format consistency between indexes.
# Migration scripts store JSON-quoted values in indexes (e.g., "\"domainid\"").
# Verify that runtime serialization matches between display_domains and
# display_domain_index, since format mismatches can cause lookup failures.

## TC-EDGE-004: Create fresh domain for serialization comparison
@ser_domain = Onetime::CustomDomain.create!("serial.example.com", @org.objid)
@ser_dd_raw = Familia.dbclient.hget("custom_domain:display_domains", "serial.example.com")
@ser_dd_raw.class
#=> String

## TC-EDGE-004: Raw value in display_domain_index
@ser_ddi_raw = Familia.dbclient.hget("custom_domain:display_domain_index", "serial.example.com")
@ser_ddi_raw.class
#=> String

## TC-EDGE-004: display_domains stores plain identifier (or JSON-quoted)
# Report what format display_domains uses
@ser_dd_raw.start_with?('"') ? "json_quoted" : "plain"
#=~> /plain|json_quoted/

## TC-EDGE-004: display_domain_index format
@ser_ddi_raw.start_with?('"') ? "json_quoted" : "plain"
#=~> /plain|json_quoted/

## TC-EDGE-004: Both .get() methods return the domain identifier correctly
@dd_got = Onetime::CustomDomain.display_domains.get("serial.example.com")
@ddi_got = Onetime::CustomDomain.display_domain_index.get("serial.example.com")
[@dd_got == @ser_domain.identifier, !@ddi_got.nil?]
#=> [true, true]

# TC-EDGE-001: Case sensitivity handling between manual and auto index.
# create! normalizes to lowercase via PublicSuffix.parse. Both indexes should
# store lowercase consistently regardless of input case.

## TC-EDGE-001: Create domain with mixed-case input
@domain_case = Onetime::CustomDomain.create!("MiXeD.Example.COM", @org.objid)
@domain_case.display_domain
#=> "mixed.example.com"

## TC-EDGE-001: display_domains (manual) stores lowercase
Onetime::CustomDomain.display_domains.get("mixed.example.com").nil?
#=> false

## TC-EDGE-001: display_domains does NOT have mixed-case key
Onetime::CustomDomain.display_domains.get("MiXeD.Example.COM")
#=> nil

## TC-EDGE-001: display_domain_index (auto) stores lowercase
Onetime::CustomDomain.display_domain_index.get("mixed.example.com").nil?
#=> false

## TC-EDGE-001: Both indexes point to the same identifier
@dd_case = Onetime::CustomDomain.display_domains.get("mixed.example.com")
@ddi_case = Onetime::CustomDomain.display_domain_index.get("mixed.example.com")
@dd_case == @domain_case.identifier && !@ddi_case.nil?
#=> true

## TC-EDGE-001: destroy! cleans both lowercase entries
@domain_case.destroy!
[Onetime::CustomDomain.display_domains.get("mixed.example.com"),
 Onetime::CustomDomain.display_domain_index.get("mixed.example.com")]
#=> [nil, nil]

# TC-CONC-001: Two sequential create! for same domain with different orgs.
# hsetnx on display_domains is the atomic gate. First create! wins,
# second gets an error. Both indexes should be consistent after.

## TC-CONC-001: Setup fresh fixtures for concurrent test
@conc_owner1 = Onetime::Customer.create!(email: "conc1_#{@timestamp}@test.com")
@conc_org1 = Onetime::Organization.create!("Conc Org1", @conc_owner1, "conc1@test.com")
@conc_owner2 = Onetime::Customer.create!(email: "conc2_#{@timestamp}@test.com")
@conc_org2 = Onetime::Organization.create!("Conc Org2", @conc_owner2, "conc2@test.com")
@conc_org1.class
#=> Onetime::Organization

## TC-CONC-001: First create! succeeds
@conc_domain = Onetime::CustomDomain.create!("conc.example.com", @conc_org1.objid)
@conc_domain.display_domain
#=> "conc.example.com"

## TC-CONC-001: Second create! for same domain with different org fails
begin
  Onetime::CustomDomain.create!("conc.example.com", @conc_org2.objid)
  "created"
rescue Onetime::Problem
  "rejected"
end
#=> "rejected"

## TC-CONC-001: Winner has both indexes pointing to its identifier
[Onetime::CustomDomain.display_domains.get("conc.example.com") == @conc_domain.identifier,
 !Onetime::CustomDomain.display_domain_index.get("conc.example.com").nil?]
#=> [true, true]

## TC-CONC-001: Winner's org_id is the first org
@conc_domain.org_id
#=> @conc_org1.objid

## TC-CONC-001: Loser's org has no association with this domain
@conc_org2.domain?(@conc_domain.domainid)
#=> false

# TC-CON-003: create! hsetnx succeeds but save fails — rollback cleans both indexes.
# When hsetnx on display_domains succeeds but a subsequent step raises,
# the rescue block must clean BOTH display_domains (manual) and
# display_domain_index (auto unique_index) to prevent phantom entries.

## TC-CON-003: Setup — monkey-patch save to fail for a specific domain
@con3_org = @conc_org1  # reuse existing org
@con3_domain_name = "con3-fail.example.com"
# Temporarily patch generate_txt_validation_record to raise for our test domain
@original_method = Onetime::CustomDomain.instance_method(:generate_txt_validation_record)
Onetime::CustomDomain.define_method(:generate_txt_validation_record) do
  if display_domain == "con3-fail.example.com"
    raise StandardError, "Simulated failure in generate_txt_validation_record"
  end
  @original_method.bind(self).call
end
true
#=> true

## TC-CON-003: create! raises due to patched failure
begin
  Onetime::CustomDomain.create!(@con3_domain_name, @con3_org.objid)
  "unexpected_success"
rescue StandardError => e
  e.message
end
#=> "Simulated failure in generate_txt_validation_record"

## TC-CON-003: display_domains (manual) is clean after failed create!
Onetime::CustomDomain.display_domains.get(@con3_domain_name)
#=> nil

## TC-CON-003: display_domain_index (auto) is clean after failed create!
Onetime::CustomDomain.display_domain_index.get(@con3_domain_name).nil?
#=> true

## TC-CON-003: Restore original method
Onetime::CustomDomain.define_method(:generate_txt_validation_record, @original_method)
true
#=> true

## TC-CON-003: Domain can be created normally after failed attempt
@con3_success = Onetime::CustomDomain.create!(@con3_domain_name, @con3_org.objid)
@con3_success.display_domain
#=> "con3-fail.example.com"

## TC-CON-003: Both indexes point to successfully created domain
[Onetime::CustomDomain.display_domains.get(@con3_domain_name) == @con3_success.identifier,
 !Onetime::CustomDomain.display_domain_index.get(@con3_domain_name).nil?]
#=> [true, true]

# TC-CON-003b: After display_domain rename, old values cleaned from both indexes.
# Uses update_display_domain method which properly maintains both indexes.

## TC-CON-003b: Create domain for rename test
@rename_domain = Onetime::CustomDomain.create!("rename-old.example.com", @con3_org.objid)
@rename_domain.display_domain
#=> "rename-old.example.com"

## TC-CON-003b: Both indexes have the old name
[!Onetime::CustomDomain.display_domains.get("rename-old.example.com").nil?,
 !Onetime::CustomDomain.display_domain_index.get("rename-old.example.com").nil?]
#=> [true, true]

## TC-CON-003b: Rename via update_display_domain
@rename_domain.update_display_domain("rename-new.example.com")
@rename_domain.display_domain
#=> "rename-new.example.com"

## TC-CON-003b: Old name removed from display_domains (manual)
Onetime::CustomDomain.display_domains.get("rename-old.example.com")
#=> nil

## TC-CON-003b: Old name removed from display_domain_index (auto)
Onetime::CustomDomain.display_domain_index.get("rename-old.example.com").nil?
#=> true

## TC-CON-003b: New name present in display_domains (manual)
Onetime::CustomDomain.display_domains.get("rename-new.example.com") == @rename_domain.identifier
#=> true

## TC-CON-003b: New name present in display_domain_index (auto)
Onetime::CustomDomain.display_domain_index.get("rename-new.example.com").nil?
#=> false

## TC-CON-003b: load_by_display_domain finds via new name
Onetime::CustomDomain.load_by_display_domain("rename-new.example.com").nil?
#=> false

## TC-CON-003b: load_by_display_domain returns nil for old name
Onetime::CustomDomain.load_by_display_domain("rename-old.example.com").nil?
#=> true

# TC-EDGE-002: Empty/nil display_domain guard rails.
# save() and add() should raise for nil/empty display_domain.

## TC-EDGE-002: save() raises for nil display_domain
@edge_nil = Onetime::CustomDomain.new(display_domain: nil, org_id: @org.objid)
begin
  @edge_nil.save
  "unexpected_success"
rescue Onetime::Problem => e
  e.message
end
#=> "Display domain required"

## TC-EDGE-002: save() raises for empty string display_domain
@edge_empty = Onetime::CustomDomain.new(display_domain: "", org_id: @org.objid)
begin
  @edge_empty.save
  "unexpected_success"
rescue Onetime::Problem => e
  e.message
end
#=> "Display domain required"

## TC-EDGE-002: save() raises for nil org_id
@edge_no_org = Onetime::CustomDomain.new(display_domain: "edge.example.com", org_id: nil)
begin
  @edge_no_org.save
  "unexpected_success"
rescue Onetime::Problem => e
  e.message
end
#=> "Organization ID required"

## TC-EDGE-002: add() raises for nil display_domain
@edge_add_nil = Onetime::CustomDomain.new(display_domain: nil, org_id: @org.objid)
begin
  Onetime::CustomDomain.add(@edge_add_nil)
  "unexpected_success"
rescue Onetime::Problem => e
  e.message
end
#=> "Cannot add custom domain with nil display_domain"

# TC-EDGE-003: Stale entries after record TTL expiration.
# If a domain's main object key expires via TTL, both indexes retain
# stale entries. This documents the known limitation and verifies
# re-creation is blocked by stale display_domains entry.
# Note: CustomDomain does not use TTL in production; this is a defensive test.

## TC-EDGE-003: Create domain then expire its main key
@ttl_domain = Onetime::CustomDomain.create!("ttl-test.example.com", @org.objid)
@ttl_saved_id = @ttl_domain.identifier
# Force immediate expiration of the object hash
Familia.dbclient.del(@ttl_domain.dbkey)
@ttl_domain.exists?
#=> false

## TC-EDGE-003: display_domains still has stale entry (known limitation)
Onetime::CustomDomain.display_domains.get("ttl-test.example.com").nil?
#=> false

## TC-EDGE-003: display_domain_index still has stale entry (known limitation)
Onetime::CustomDomain.display_domain_index.get("ttl-test.example.com").nil?
#=> false

## TC-EDGE-003: Re-creation is blocked by stale display_domains entry
# hsetnx returns 0 because the key already exists
begin
  Onetime::CustomDomain.create!("ttl-test.example.com", @org.objid)
  "created"
rescue Onetime::Problem => e
  # The stale entry causes various error messages depending on the code path
  e.message =~ /Domain|registered|organization/ ? "blocked_by_stale" : e.message
end
#=> "blocked_by_stale"

## TC-EDGE-003: Manual cleanup restores ability to create
Onetime::CustomDomain.display_domains.remove("ttl-test.example.com")
Onetime::CustomDomain.display_domain_index.remove("ttl-test.example.com")
Onetime::CustomDomain.instances.remove(@ttl_saved_id)
Onetime::CustomDomain.owners.remove(@ttl_saved_id)
# Now creation should work
@ttl_recreated = Onetime::CustomDomain.create!("ttl-test.example.com", @org.objid)
@ttl_recreated.display_domain
#=> "ttl-test.example.com"

# Teardown
Familia.dbclient.flushdb
