# try/unit/operations/domain_toolbox_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for the extracted domain-toolbox operations (epic #43):
#   Onetime::Operations::Domains::{Probe, OrphanedScan, Repair, Transfer}
#
# These are the SINGLE implementation of the toolbox verbs (the `bin/ots domains
# {probe,orphaned,repair,transfer}` CLI + the colonel endpoints are thin
# adapters). Covers, per CONTRACT 4:
# - READ-ONLY ops (Probe, OrphanedScan) record NO audit events.
# - Repair/Transfer dry-run: compute a plan, mutate NOTHING, audit NOTHING.
# - Repair/Transfer apply: mutate + record EXACTLY ONE audit event.
# - Repair no-op (no issues) records no audit event.
# - Repair :needs_org and Transfer :mismatch are REFUSED privileged mutations:
#   they mutate nothing but each record ONE result: :failure event, same verb
#   and target as a success. A refusal that returns a Result must be as
#   traceable as one that raises.
# - A Transfer that blows up mid-apply records ONE result: :failure event via
#   Onetime::AuditedFailure and re-raises (the success-path record never runs).
#
# Run: try --agent try/unit/operations/domain_toolbox_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/domains/probe'
require 'onetime/operations/domains/orphaned_scan'
require 'onetime/operations/domains/repair'
require 'onetime/operations/domains/transfer'

AE = Onetime::AdminAuditEvent

@actor = 'ur1colonelpub' # a PUBLIC id (extid-shaped), never an objid

@test_id = SecureRandom.hex(4)
@cust1   = Onetime::Customer.create!(email: "dtcust1_#{@test_id}@example.com")
@cust2   = Onetime::Customer.create!(email: "dtcust2_#{@test_id}@example.com")
@org1    = Onetime::Organization.create!("DT Org 1 #{@test_id}", @cust1, "billing+dt1+#{@test_id}@onetimesecret.com")
@org2    = Onetime::Organization.create!("DT Org 2 #{@test_id}", @cust2, "billing+dt2+#{@test_id}@onetimesecret.com")

AE.events.clear

# ---- Probe: read-only, no audit ---------------------------------------

## Probe returns a result Hash with a health classification
@probe = Onetime::Operations::Domains::Probe.new(
  hostname: "no-such-host-#{@test_id}.invalid", timeout: 2,
).call
@probe[:health].is_a?(String)
#=> true

## an unresolvable host classifies as a DNS error (fails fast, no network)
@probe[:health]
#=> "dns_error"

## a probe records NO audit event (read-only)
AE.count
#=> 0

# ---- OrphanedScan: read-only, no audit --------------------------------

## an orphaned domain (blank org_id) shows up in the scan
# The model's #save refuses a blank org_id, so an orphaned record (a data-drift
# state) is produced by clearing the field directly in the store, then reloading.
@orphan_seed = Onetime::CustomDomain.create!("dt-orphan-#{@test_id}.example.com", @org1.objid)
Familia.dbclient.hset(@orphan_seed.dbkey, 'org_id', '')
@orphan = Onetime::CustomDomain.find_by_identifier(@orphan_seed.domainid)
@scan = Onetime::Operations::Domains::OrphanedScan.new(per_page: nil).call
@scan.domains.map { |d| d[:domain_id] }.include?(@orphan.domainid)
#=> true

## the orphaned summary carries the public extid + display_domain
@row = @scan.domains.find { |d| d[:domain_id] == @orphan.domainid }
[@row[:extid] == @orphan.extid, @row[:display_domain] == @orphan.display_domain]
#=> [true, true]

## the scan records NO audit event (read-only)
AE.count
#=> 0

# ---- Repair: dry-run computes, mutates/audits nothing -----------------

## a domain with org_id set but missing from the collection is an issue
# parse + save persists the record WITHOUT adding it to the org's domains
# collection (unlike create!), reproducing the not-in-collection drift.
@dom = Onetime::CustomDomain.parse("dt-repair-#{@test_id}.example.com", @org1.org_id)
@dom.save
@in_before = @org1.list_domains.map(&:domainid).include?(@dom.domainid)
@in_before
#=> false

## dry-run finds the not-in-collection issue and plans (no mutation)
@plan = Onetime::Operations::Domains::Repair.new(domain: @dom, actor: @actor, dry_run: true).call
[@plan.status, @plan.issues.size]
#=> [:planned, 1]

## a dry-run records NO audit event
AE.count
#=> 0

## the domain is still NOT in the collection after a dry-run (nothing mutated)
@org1.list_domains.map(&:domainid).include?(@dom.domainid)
#=> false

# ---- Repair: apply mutates + audits exactly once ----------------------

## applying the repair adds the domain to the org collection
@applied = Onetime::Operations::Domains::Repair.new(domain: @dom, actor: @actor, dry_run: false).call
@applied.status
#=> :repaired

## the domain is now in the org's collection (model actually mutated)
@org1.list_domains.map(&:domainid).include?(@dom.domainid)
#=> true

## exactly ONE audit event was recorded for the repair
AE.count
#=> 1

## the audit event is the repair verb, targeting the domain extid, public actor
@ev = AE.recent(1).first
[@ev['verb'], @ev['target'], @ev['actor']]
#=> ["domain.repair", @dom.extid, "ur1colonelpub"]

# ---- Repair: no-op (already consistent) records no audit --------------

## re-running repair on the now-consistent domain finds no issues
AE.events.clear
@noop = Onetime::Operations::Domains::Repair.new(domain: @dom, actor: @actor, dry_run: false).call
@noop.status
#=> :no_issues

## a no-issue repair records NO audit event
AE.count
#=> 0

# ---- Repair: orphaned needs a target org ------------------------------

## an orphaned domain with no target org is blocked (:needs_org)
AE.events.clear
@nblk = Onetime::Operations::Domains::Repair.new(domain: @orphan, actor: @actor, dry_run: false).call
[@nblk.status, AE.count]
#=> [:needs_org, 1]

## the refusal is recorded as a FAILURE on the repair verb, targeting the domain
@nev = AE.recent(1).first
[@nev['verb'], @nev['target'], @nev['result'], @nev['detail']['reason']]
#=> ["domain.repair", @orphan.extid, "failure", "needs_org"]

# ---- Transfer: dry-run computes, mutates/audits nothing ---------------

## set up a domain owned by org1 and present in its collection
@tdom = Onetime::CustomDomain.create!("dt-transfer-#{@test_id}.example.com", @org1.objid)
@org1.add_domain(@tdom)
AE.events.clear
@tplan = Onetime::Operations::Domains::Transfer.new(
  domain: @tdom, to_org: @org2, actor: @actor, dry_run: true,
).call
[@tplan.status, @tplan.to_org_id == @org2.org_id]
#=> [:planned, true]

## a dry-run transfer records NO audit and leaves ownership unchanged
[AE.count, @tdom.org_id == @org1.org_id]
#=> [0, true]

# ---- Transfer: apply mutates + audits exactly once --------------------

## applying the transfer moves the domain to org2
@tapplied = Onetime::Operations::Domains::Transfer.new(
  domain: @tdom, to_org: @org2, actor: @actor, dry_run: false,
).call
@tapplied.status
#=> :transferred

## the domain now belongs to org2 (org_id updated)
reloaded = Onetime::CustomDomain.load_by_display_domain(@tdom.display_domain)
reloaded.org_id == @org2.org_id
#=> true

## the domain is in org2's collection and gone from org1's
[@org2.list_domains.map(&:domainid).include?(@tdom.domainid),
 @org1.list_domains.map(&:domainid).include?(@tdom.domainid)]
#=> [true, false]

## exactly ONE audit event was recorded for the transfer
AE.count
#=> 1

## the audit event is the transfer verb targeting the domain extid
@tev = AE.recent(1).first
[@tev['verb'], @tev['target'], @tev['actor']]
#=> ["domain.transfer", @tdom.extid, "ur1colonelpub"]

# ---- Transfer: explicit from_org mismatch is blocked ------------------

## an explicit from_org that isn't the current owner is a :mismatch
AE.events.clear
@mm = Onetime::Operations::Domains::Transfer.new(
  domain: @tdom, to_org: @org1, from_org: @org1, actor: @actor, dry_run: false,
).call
[@mm.status, AE.count]
#=> [:mismatch, 1]

## the refusal is recorded as a FAILURE on the transfer verb, targeting the domain
@mmev = AE.recent(1).first
[@mmev['verb'], @mmev['target'], @mmev['result'], @mmev['detail']['reason']]
#=> ["domain.transfer", @tdom.extid, "failure", "mismatch"]

# ---- Transfer: a raise mid-apply is audited, then re-raised -----------
#
# The Onetime::AuditedFailure mechanism. The success-path record sits AFTER
# the collection add, so without the macro a transfer that rolls back leaves
# no trace at all. A frozen destination org makes add_domain blow up.

## a transfer that raises mid-apply re-raises the original error
AE.events.clear
@boom_org = Onetime::Organization.load(@org1.objid)
@boom_org.define_singleton_method(:add_domain) { |*| raise(Onetime::Problem, 'collection add exploded') }
begin
  Onetime::Operations::Domains::Transfer.new(
    domain: @tdom, to_org: @boom_org, actor: @actor, dry_run: false,
  ).call
  :no_raise
rescue StandardError => ex
  ex.class.to_s
end
#=> "RuntimeError"

## it recorded EXACTLY ONE result: :failure event with the unchanged verb/target
@bev = AE.recent(1).first
[AE.count, @bev['verb'], @bev['target'], @bev['result'], @bev['detail']['dry_run']]
#=> [1, "domain.transfer", @tdom.extid, "failure", false]

# ---- Cleanup ----------------------------------------------------------

[@orphan, @dom, @tdom].compact.each { |d| d.destroy! rescue nil }
[@org1, @org2].compact.each { |o| o.destroy! rescue nil }
[@cust1, @cust2].compact.each { |c| c.destroy! rescue nil }
AE.events.clear
