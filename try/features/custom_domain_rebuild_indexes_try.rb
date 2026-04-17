# try/features/custom_domain_rebuild_indexes_try.rb
#
# frozen_string_literal: true

# Rebuild script tests: verifies that rebuild_custom_domain_indexes.rb
# reconstructs all CustomDomain index structures from the canonical
# :object hashes, never reading from the target structures as input.

require 'stringio'
require_relative '../support/test_helpers'
require_relative '../../scripts/upgrades/v0.24.5/rebuild_custom_domain_indexes'

OT.boot! :test, false
Familia.dbclient.flushdb

Rebuilder = Onetime::CustomDomain::IndexRebuilder

def capture_run(execute:)
  io = StringIO.new
  result = Rebuilder.run(execute: execute, verbose: false, io: io)
  [result, io.string]
end

def content_commands(output)
  output.lines.map(&:chomp).reject { |l| l.empty? || l.start_with?('#', '[') || l.start_with?('===', 'instances', 'display_', 'owners', 'extid_', 'organization_', 'commands_', 'elapsed') }
end

@ts = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "rebuild_#{@ts}@test.com")
@org = Onetime::Organization.create!("Rebuild Org #{@ts}", @owner, "rebuild_#{@ts}@test.com")

## SCENARIO 1: Clean round-trip - rebuilder is non-destructive on healthy data
@domain_clean = Onetime::CustomDomain.create!("clean-#{@ts}.example.com", @org.objid)
@snap_instances_before = Onetime::CustomDomain.instances.members.dup
@snap_ddi_before       = Onetime::CustomDomain.display_domain_index.get("clean-#{@ts}.example.com")
@snap_dd_before        = Onetime::CustomDomain.display_domains.get("clean-#{@ts}.example.com")
@snap_owners_before    = Onetime::CustomDomain.owners.get(@domain_clean.identifier)
_result, _out = capture_run(execute: true)
[
  Onetime::CustomDomain.instances.members == @snap_instances_before,
  Onetime::CustomDomain.display_domain_index.get("clean-#{@ts}.example.com") == @snap_ddi_before,
  Onetime::CustomDomain.display_domains.get("clean-#{@ts}.example.com") == @snap_dd_before,
  Onetime::CustomDomain.owners.get(@domain_clean.identifier) == @snap_owners_before
]
#=> [true, true, true, true]

## SCENARIO 1b: Idempotence - final state identical after a second execute run
# Note: the design invariant ("no reads from target structures") means dry-run
# will always emit writes. True idempotence here = stable final state.
@before_ddi = Familia.dbclient.hgetall('custom_domain:display_domain_index')
@before_dd  = Familia.dbclient.hgetall('custom_domain:display_domains')
@before_ow  = Familia.dbclient.hgetall('custom_domain:owners')
@before_ex  = Familia.dbclient.hgetall('custom_domain:extid_lookup')
@before_in  = Familia.dbclient.zrange('custom_domain:instances', 0, -1, with_scores: true)
capture_run(execute: true)
[
  Familia.dbclient.hgetall('custom_domain:display_domain_index') == @before_ddi,
  Familia.dbclient.hgetall('custom_domain:display_domains') == @before_dd,
  Familia.dbclient.hgetall('custom_domain:owners') == @before_ow,
  Familia.dbclient.hgetall('custom_domain:extid_lookup') == @before_ex,
  Familia.dbclient.zrange('custom_domain:instances', 0, -1, with_scores: true) == @before_in,
]
#=> [true, true, true, true, true]

## SCENARIO 2a: Split-brain - corrupt indexes manually
@domain_a = Onetime::CustomDomain.create!("split-a-#{@ts}.example.com", @org.objid)
@domain_b = Onetime::CustomDomain.create!("split-b-#{@ts}.example.com", @org.objid)
@fqdn_a = "split-a-#{@ts}.example.com"
Familia.dbclient.hset('custom_domain:display_domain_index', @fqdn_a, '"fake-uuid-1"')
Familia.dbclient.hset('custom_domain:display_domains', @fqdn_a, '"fake-uuid-2"')
Familia.dbclient.zadd('custom_domain:instances', 0, "phantom-objid-#{@ts}")
# Seed a missing entry: create :object hash whose objid is absent from instances
@orphan_objid = "orphan-#{@ts}"
Familia.dbclient.hset("custom_domain:#{@orphan_objid}:object",
  { 'objid' => @orphan_objid.to_json,
    'display_domain' => "orphan-#{@ts}.example.com".to_json,
    'org_id' => @org.objid.to_json,
    'created' => Familia.now.to_i.to_json })
Familia.dbclient.zadd('custom_domain:instances', Familia.now.to_i, @orphan_objid) ? 'seeded' : 'seeded'
# Remove orphan from instances to test the "missing" case
Familia.dbclient.zrem('custom_domain:instances', @orphan_objid)
true
#=> true

## SCENARIO 2b: After rebuild, indexes agree with :object.objid
capture_run(execute: true)
[
  Onetime::CustomDomain.display_domain_index.get(@fqdn_a).to_s.include?(@domain_a.identifier),
  Onetime::CustomDomain.display_domains.get(@fqdn_a) == @domain_a.identifier,
  Onetime::CustomDomain.owners.get(@domain_a.identifier) == @org.objid,
]
#=> [true, true, true]

## SCENARIO 2c: Phantom removed from instances
Onetime::CustomDomain.instances.member?("phantom-objid-#{@ts}")
#=> false

## SCENARIO 2d: Missing entry added to instances
Onetime::CustomDomain.instances.member?(@orphan_objid)
#=> true

## SCENARIO 3: Empty-objid :object hash is skipped (logged, not synthesized)
Familia.dbclient.hset("custom_domain:no-objid-#{@ts}:object",
  { 'display_domain' => "badkey-#{@ts}.example.com".to_json, 'org_id' => @org.objid.to_json })
# objid field intentionally absent
_result3, out3 = capture_run(execute: true)
in_instances = Onetime::CustomDomain.instances.member?("no-objid-#{@ts}")
has_fqdn = !Onetime::CustomDomain.display_domain_index.get("badkey-#{@ts}.example.com").nil?
warned = out3.lines.any? { |l| l.include?('WARN') && l.include?("no-objid-#{@ts}") }
[in_instances, has_fqdn, warned]
#=> [false, false, true]

## SCENARIO 4: Idempotence - final state stable across two execute runs
Familia.dbclient.del("custom_domain:no-objid-#{@ts}:object")  # clean up empty objid fixture
capture_run(execute: true)
@s4_ddi = Familia.dbclient.hgetall('custom_domain:display_domain_index')
@s4_dd  = Familia.dbclient.hgetall('custom_domain:display_domains')
@s4_in  = Familia.dbclient.zrange('custom_domain:instances', 0, -1)
capture_run(execute: true)
[
  Familia.dbclient.hgetall('custom_domain:display_domain_index') == @s4_ddi,
  Familia.dbclient.hgetall('custom_domain:display_domains') == @s4_dd,
  Familia.dbclient.zrange('custom_domain:instances', 0, -1) == @s4_in,
]
#=> [true, true, true]

## SCENARIO 5a: Orphaned org-domains key is deleted
Familia.dbclient.zadd("organization:fake-org-#{@ts}:domains", Familia.now.to_i, "fake-domain-#{@ts}")
Familia.dbclient.exists?("organization:fake-org-#{@ts}:domains")
#=> true

## SCENARIO 5b: After rebuild, orphan key is gone
capture_run(execute: true)
Familia.dbclient.exists?("organization:fake-org-#{@ts}:domains")
#=> false

## SCENARIO 5c: Live org's domains key was not deleted
Familia.dbclient.exists?("organization:#{@org.objid}:domains")
#=> true

## SCENARIO 6: Dry-run does not mutate Redis state
@s6_ddi = Familia.dbclient.hgetall('custom_domain:display_domain_index')
@s6_dd  = Familia.dbclient.hgetall('custom_domain:display_domains')
@s6_in  = Familia.dbclient.zrange('custom_domain:instances', 0, -1, with_scores: true)
@s6_ow  = Familia.dbclient.hgetall('custom_domain:owners')
capture_run(execute: false)
[
  Familia.dbclient.hgetall('custom_domain:display_domain_index') == @s6_ddi,
  Familia.dbclient.hgetall('custom_domain:display_domains') == @s6_dd,
  Familia.dbclient.zrange('custom_domain:instances', 0, -1, with_scores: true) == @s6_in,
  Familia.dbclient.hgetall('custom_domain:owners') == @s6_ow,
]
#=> [true, true, true, true]

## SCENARIO 7a: Orphaned member inside a live org's sorted set is purged
Familia.dbclient.zadd("organization:#{@org.objid}:domains", 0, "stale-member-#{@ts}")
Familia.dbclient.zscore("organization:#{@org.objid}:domains", "stale-member-#{@ts}").nil?
#=> false

## SCENARIO 7b: After rebuild, the orphan member is gone (swap replaces set entirely)
capture_run(execute: true)
Familia.dbclient.zscore("organization:#{@org.objid}:domains", "stale-member-#{@ts}")
#=> nil

## SCENARIO 8: Record with objid but missing display_domain is included in
## instances/owners but not in display_domain_index/display_domains.
@malformed_objid = "no-fqdn-#{@ts}"
Familia.dbclient.hset("custom_domain:#{@malformed_objid}:object",
  { 'objid' => @malformed_objid.to_json,
    'org_id' => @org.objid.to_json,
    'created' => Familia.now.to_i.to_json })
capture_run(execute: true)
[
  Onetime::CustomDomain.instances.member?(@malformed_objid),
  Onetime::CustomDomain.owners.get(@malformed_objid) == @org.objid,
  Onetime::CustomDomain.display_domain_index.hgetall.value?(@malformed_objid),
  Onetime::CustomDomain.display_domains.hgetall.value?(@malformed_objid),
]
#=> [true, true, false, false]

# Teardown
Familia.dbclient.flushdb
