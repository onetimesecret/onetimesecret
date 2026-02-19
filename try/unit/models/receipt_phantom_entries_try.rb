# try/unit/models/receipt_phantom_entries_try.rb
#
# frozen_string_literal: true

# QA tests for phantom ZSET entry invariants in Receipt participation.
#
# Three-way consistency between:
#   1. Domain ZSETs (custom_domain:{id}:receipts)
#   2. Receipt hash domain_id field
#   3. Participations set (receipt:{id}:participations)
#
# Covers:
# - Receipt with nil domain_id must not be in any domain ZSET
# - Receipt with valid domain_id must be in exactly that domain's ZSET
# - destroy! with nil domain_id doesn't error
# - destroy! with valid domain_id removes from domain ZSET
# - Inconsistent state detection when domain_id is cleared after ZSET addition
# - Domain deletion leaves receipts in a recoverable state
# - Participations set tracks domain ZSET membership (three-way check)
# - Participations drift detection when ZSET and participations disagree

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for phantom entries tests'

@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "phantom_entries_#{@timestamp}@test.com")
@org = Onetime::Organization.create!('Phantom Entries Org', @owner, "phantom_entries@test-#{@timestamp}.com")
@domain = Onetime::CustomDomain.create!("phantom-entries-#{@timestamp}.test.com", @org.objid)

## Receipt with nil domain_id has no domain participation
@receipt_nil, @secret_nil = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'nil domain secret')
@receipt_nil.org_id = @org.objid
@receipt_nil.save
@receipt_nil.add_to_organization_receipts(@org)
@receipt_nil.domain_id.nil?
#=> true

## Receipt with nil domain_id must NOT be in domain's receipts ZSET
@domain.receipt?(@receipt_nil.objid)
#=> false

## Receipt with nil domain_id has empty custom_domain_instances
@receipt_nil.custom_domain_instances.size
#=> 0

## Receipt with valid domain_id is properly enrolled in domain ZSET
@receipt_valid, @secret_valid = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'valid domain secret', domain: @domain.display_domain)
@receipt_valid.org_id = @org.objid
@receipt_valid.domain_id = @domain.objid
@receipt_valid.save
@receipt_valid.add_to_organization_receipts(@org)
@receipt_valid.add_to_custom_domain_receipts(@domain)
@domain.receipt?(@receipt_valid.objid)
#=> true

## Receipt with valid domain_id is in exactly one domain's ZSET
@receipt_valid.custom_domain_instances.size
#=> 1

## Receipt with valid domain_id references the correct domain
@receipt_valid.custom_domain_instances.first.objid
#=> @domain.objid

## Receipt with valid domain_id is NOT in a different domain's ZSET
@domain2 = Onetime::CustomDomain.create!("other-phantom-#{@timestamp}.test.com", @org.objid)
@domain2.receipt?(@receipt_valid.objid)
#=> false

## destroy! with nil domain_id does not raise an error
@receipt_destroy_nil, @secret_destroy_nil = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'destroy nil domain')
@receipt_destroy_nil.org_id = @org.objid
@receipt_destroy_nil.save
@receipt_destroy_nil.add_to_organization_receipts(@org)
begin
  @receipt_destroy_nil.destroy!
  true
rescue => e
  e.message
end
#=> true

## destroy! with nil domain_id removed receipt from org ZSET
@org.receipt?(@receipt_destroy_nil.objid)
#=> false

## destroy! with valid domain_id removes from domain ZSET
@receipt_destroy_valid, @secret_destroy_valid = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'destroy valid domain', domain: @domain.display_domain)
@receipt_destroy_valid.org_id = @org.objid
@receipt_destroy_valid.domain_id = @domain.objid
@receipt_destroy_valid.save
@receipt_destroy_valid.add_to_organization_receipts(@org)
@receipt_destroy_valid.add_to_custom_domain_receipts(@domain)
@domain.receipt?(@receipt_destroy_valid.objid)
#=> true

## Confirm destroy! removes from domain ZSET
@receipt_destroy_valid.destroy!
@domain.receipt?(@receipt_destroy_valid.objid)
#=> false

## Detect inconsistent state: add to ZSET then clear domain_id
@receipt_inconsistent, @secret_inconsistent = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'inconsistent state')
@receipt_inconsistent.org_id = @org.objid
@receipt_inconsistent.domain_id = @domain.objid
@receipt_inconsistent.save
@receipt_inconsistent.add_to_organization_receipts(@org)
@receipt_inconsistent.add_to_custom_domain_receipts(@domain)
@domain.receipt?(@receipt_inconsistent.objid)
#=> true

## After clearing domain_id, receipt is still in ZSET (inconsistent state)
@receipt_inconsistent.domain_id = nil
@receipt_inconsistent.save
@domain.receipt?(@receipt_inconsistent.objid)
#=> true

## The inconsistency: domain_id is nil but ZSET membership persists
@receipt_inconsistent.domain_id.nil?
#=> true

## Reverse lookup still finds the domain via ZSET membership
@receipt_inconsistent.custom_domain_instances.size
#=> 1

## destroy! cleans up ZSET entry even with nil domain_id (via reverse lookup)
@receipt_inconsistent.destroy!
@domain.receipt?(@receipt_inconsistent.objid)
#=> false

## Receipt referencing a deleted domain: domain_id becomes stale
@stale_domain = Onetime::CustomDomain.create!("stale-#{@timestamp}.test.com", @org.objid)
@receipt_stale, @secret_stale = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'stale domain ref', domain: @stale_domain.display_domain)
@receipt_stale.org_id = @org.objid
@receipt_stale.domain_id = @stale_domain.objid
@receipt_stale.save
@receipt_stale.add_to_organization_receipts(@org)
@receipt_stale.add_to_custom_domain_receipts(@stale_domain)
@stale_domain_objid = @stale_domain.objid
@stale_domain.destroy!
@receipt_stale.domain_id
#=> @stale_domain_objid

## Stale domain reference: domain no longer exists
@stale_domain_check = Onetime::CustomDomain.new(objid: @stale_domain_objid)
@stale_domain_check.exists?
#=> false

## destroy! with stale domain_id does not error (reverse lookup handles it)
begin
  @receipt_stale.destroy!
  true
rescue => e
  e.message
end
#=> true

## Three-way check: participations set tracks domain ZSET membership
# Familia v2 stores participations members as JSON-encoded strings (quoted)
@receipt_3way, @secret_3way = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'three-way check', domain: @domain.display_domain)
@receipt_3way.org_id = @org.objid
@receipt_3way.domain_id = @domain.objid
@receipt_3way.save
@receipt_3way.add_to_organization_receipts(@org)
@receipt_3way.add_to_custom_domain_receipts(@domain)
@domain_zset_key = "custom_domain:#{@domain.objid}:receipts"
@part_key = "receipt:#{@receipt_3way.objid}:participations"
@part_members = Familia.dbclient.smembers(@part_key)
@domain_entries = @part_members.select { |m| m.include?('custom_domain:') }
@domain_entries.size
#=> 1

## Participations domain entry references the correct ZSET key
@domain_entries.first.include?(@domain.objid)
#=> true

## Receipt with nil domain_id has no domain entry in participations set
@part_key_nil = "receipt:#{@receipt_nil.objid}:participations"
@nil_parts = Familia.dbclient.smembers(@part_key_nil)
@nil_domain_parts = @nil_parts.select { |m| m.include?('custom_domain:') }
@nil_domain_parts.size
#=> 0

## Simulate participations drift: raw ZADD without SADD (migration split-phase risk)
@receipt_drift, @secret_drift = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'drift test')
@receipt_drift.org_id = @org.objid
@receipt_drift.save
@receipt_drift.add_to_organization_receipts(@org)
@drift_zset_key = "custom_domain:#{@domain.objid}:receipts"
Familia.dbclient.zadd(@drift_zset_key, Familia.now.to_f, @receipt_drift.objid)
@domain.receipt?(@receipt_drift.objid)
#=> true

## Drift: receipt in ZSET but participations set has no domain entry
@drift_part_key = "receipt:#{@receipt_drift.objid}:participations"
@drift_parts = Familia.dbclient.smembers(@drift_part_key)
@drift_domain_parts = @drift_parts.select { |m| m.include?('custom_domain:') }
@drift_domain_parts.size
#=> 0

## Drift receipt has nil domain_id (phantom + drift_gone)
@receipt_drift.domain_id.nil?
#=> true

## Drift receipt's reverse lookup cannot find the domain (no participations entry)
@receipt_drift.custom_domain_instances.size
#=> 0

## Clean up drift: manual ZREM since destroy! won't find it via reverse lookup
Familia.dbclient.zrem(@drift_zset_key, @receipt_drift.objid)
@domain.receipt?(@receipt_drift.objid)
#=> false

## destroy! properly cleans up three-way consistent receipt
@receipt_3way.destroy!
@domain.receipt?(@receipt_3way.objid)
#=> false

## Participations set is cleaned after destroy
Familia.dbclient.exists?(@part_key)
#=> false

# Teardown
@secret_nil.destroy! if @secret_nil&.exists?
@secret_valid.destroy! if @secret_valid&.exists?
@secret_destroy_nil.destroy! if @secret_destroy_nil&.exists?
@secret_destroy_valid.destroy! if @secret_destroy_valid&.exists?
@secret_inconsistent.destroy! if @secret_inconsistent&.exists?
@secret_stale.destroy! if @secret_stale&.exists?
@secret_3way.destroy! if @secret_3way&.exists?
@secret_drift.destroy! if @secret_drift&.exists?
@receipt_nil.destroy! if @receipt_nil&.exists?
@receipt_valid.destroy! if @receipt_valid&.exists?
@receipt_drift.destroy! if @receipt_drift&.exists?
@domain.destroy! if @domain&.exists?
@domain2.destroy! if @domain2&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
