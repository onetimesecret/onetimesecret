# try/unit/auth/operations/customers_ops_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for the customer admin operations (epic #20):
#   Auth::Operations::Customers::{List, Show, SetRole, SetVerification, Purge, Doctor}
#
# Covers:
# - List: index-backed pagination, total counts, role filter, :all mode
# - Show: resolve by extid/email, not-found, organizations summary
# - SetRole: success + EXACTLY ONE audit event, idempotent no_change (no audit),
#   invalid role rejected
# - SetVerification: success audits once, no_change does not audit
# - Purge: destroys + audits once; audit target is the (pre-destroy) extid;
#   a customer whose extid_lookup entry has DRIFTED still gets its live session
#   revoked (the op is handed the record, not an extid to re-resolve)
# - Doctor: healthy customer clean, integrity issue detected, repair audits
#
# Run: try --agent try/unit/auth/operations/customers_ops_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'web/auth/operations/customers'
require 'securerandom'
require 'onetime/operations/sessions/track_metadata'

AE = Onetime::ColonelAuditEvent

@stamp = Familia.now.to_f.to_s.gsub('.', '')

def mk(tag, stamp)
  Onetime::Customer.create!(email: "#{tag}_#{stamp}@ops.example")
end

# All fixtures created up front (Tryouts runs top-level setup once).
@list_customers = 5.times.map { |i| mk("list#{i}", @stamp) }
@list_customers[0].role = 'admin'
@list_customers[0].save

@show_cust = mk('show', @stamp)

@role_cust = mk('role', @stamp)

@ver_cust = mk('ver', @stamp)
@ver_cust.verified = 'false'
@ver_cust.save

@purge_cust  = mk('purge', @stamp)
@purge_extid = @purge_cust.extid

# EXTID-INDEX DRIFT purge regression (the gap that motivated `customer:` on
# RevokeAllForCustomer, #4205/#4217): a customer with one live TRACKED session
# whose extid_lookup entry is MISSING. Seeded BEFORE the entry is dropped
# because TrackMetadata resolves the owner via find_by_extid.
@purge_drift       = mk('purgedrift', @stamp)
@purge_drift_extid = @purge_drift.extid
@purge_drift_sid   = SecureRandom.hex(32)
Onetime::Operations::Sessions::TrackMetadata.new(
  session_id: @purge_drift_sid,
  session_data: { 'authenticated' => true, 'external_id' => @purge_drift_extid,
                  'ip_address' => '203.0.113.7', 'user_agent' => 'UA' },
).call
Familia.dbclient.set(
  "session:#{@purge_drift_sid}",
  Onetime::SessionCodec.from_config.encode({ 'authenticated' => true, 'external_id' => @purge_drift_extid }),
)
Onetime::Customer.extid_lookup.remove_field(@purge_drift_extid)

@doc_healthy = mk('doc', @stamp)

@doc_bad = mk('docbad', @stamp)
@doc_bad.role = 'admin' # not in Doctor::VALID_ROLES ([customer, anonymous, colonel])
@doc_bad.save

@doc_repair = mk('docrep', @stamp)
@doc_repair.verified = 'true'
@doc_repair.verified_by = ''
@doc_repair.save

AE.events.clear

# ---- List --------------------------------------------------------------

## List page 1 returns at most per_page customers, all Onetime::Customer
@list_page = Auth::Operations::Customers::List.new(page: 1, per_page: 2).call
[@list_page.customers.size, @list_page.customers.all? { |c| c.is_a?(Onetime::Customer) }]
#=> [2, true]

## List total_count reflects the whole instances set (>= the 5 we made)
@list_page.total_count >= 5
#=> true

## List total_pages is ceil(total_count / per_page)
@list_page.total_pages == (@list_page.total_count.to_f / 2).ceil
#=> true

## List :all returns every customer in one page (total_pages 1)
@list_all = Auth::Operations::Customers::List.new(per_page: :all).call
[@list_all.customers.size == @list_all.total_count, @list_all.total_pages]
#=> [true, 1]

## List role filter is index-backed and returns only that role
@list_admin = Auth::Operations::Customers::List.new(role: 'admin').call
@list_admin.customers.all? { |c| c.role == 'admin' } && @list_admin.customers.map(&:objid).include?(@list_customers[0].objid)
#=> true

## List blank role filter is treated as no filter
Auth::Operations::Customers::List.new(role: '').call.role
#=> nil

## List role filter stays exact under the cap and matches the true role count
# Regression guard for the #2211 residual (epic #20 CONTRACT 8): the filtered
# path now reads the role_index via a bounded, non-blocking cursor SSCAN instead
# of a blocking SMEMBERS + load-all-then-slice. A small operational-role set is
# well under ROLE_FILTER_SCAN_LIMIT, so its count is returned exactly.
@admin_count = Onetime::Customer.find_all_by_role('admin').size
[@list_admin.total_count == @admin_count, @admin_count >= 2]
#=> [true, true]

# ---- Show --------------------------------------------------------------

## Show resolves by extid and reports found?
@show_by_extid = Auth::Operations::Customers::Show.new(identifier: @show_cust.extid).call
[@show_by_extid.found?, @show_by_extid.customer.objid == @show_cust.objid]
#=> [true, true]

## Show resolves by email
Auth::Operations::Customers::Show.new(identifier: @show_cust.email).call.found?
#=> true

## Show returns found? false for an unknown identifier
Auth::Operations::Customers::Show.new(identifier: 'nobody@nowhere.example').call.found?
#=> false

## Show organizations is an array (empty for a customer with no orgs)
Auth::Operations::Customers::Show.new(customer: @show_cust).call.organizations
#=> []

# ---- SetRole (mutation + audit) ---------------------------------------

## SetRole changes the role, returns :success, and audits EXACTLY ONCE
AE.events.clear
@sr = Auth::Operations::Customers::SetRole.new(customer: @role_cust, role: 'colonel', actor: 'ur_colonel_pub').call
[@sr.status, @sr.from, @sr.to, Onetime::Customer.load(@role_cust.objid).role, AE.count]
#=> [:success, "customer", "colonel", "colonel", 1]

## the audit event has the expected verb / actor / target / detail
@sr_event = AE.recent(1).first
[@sr_event['verb'], @sr_event['actor'], @sr_event['target'], @sr_event['detail']]
#=> ["customer.set_role", "ur_colonel_pub", @role_cust.extid, { "from" => "customer", "to" => "colonel" }]

## SetRole to the same role is a no_change but STILL audits the attempt (#4337)
@sr_noop = Auth::Operations::Customers::SetRole.new(customer: @role_cust, role: 'colonel', actor: 'x').call
[@sr_noop.status, AE.count]
#=> [:no_change, 2]

## …under the same verb, marked outcome: no_change
@sr_noop_event = AE.recent(1).first
[@sr_noop_event['verb'], @sr_noop_event['result'], @sr_noop_event['detail']]
#=> ["customer.set_role", "success", { "outcome" => "no_change", "from" => "colonel", "to" => "colonel" }]

## SetRole rejects an invalid role
begin
  Auth::Operations::Customers::SetRole.new(customer: @role_cust, role: 'wizard', actor: 'x').call
  false
rescue Auth::Operations::Customers::SetRole::InvalidRole
  true
end
#=> true

# ---- SetVerification (mutation + audit, reuse) ------------------------

## SetVerification verifies, returns :success, and audits once
AE.events.clear
@sv = Auth::Operations::Customers::SetVerification.new(
  customer: @ver_cust, verified: true, actor: 'ur_colonel_pub', verified_by: 'colonel_admin'
).call
[@sv, Onetime::Customer.load(@ver_cust.objid).verified?, AE.count, AE.recent(1).first['verb'], AE.recent(1).first['detail']]
#=> [:success, true, 1, "customer.set_verification", { "verified" => true }]

## SetVerification with no state change returns :no_change but STILL audits (#4337)
@sv_noop = Auth::Operations::Customers::SetVerification.new(
  customer: @ver_cust, verified: true, actor: 'x', verified_by: 'colonel_admin'
).call
[@sv_noop, AE.count, AE.recent(1).first['detail']]
#=> [:no_change, 2, { "outcome" => "no_change", "verified" => true }]

# ---- Purge (mutation + audit, reuse DeleteCustomer) -------------------

## Purge revokes sessions before destroy and audits both mutations at the extid
AE.events.clear
@pr = Auth::Operations::Customers::Purge.new(customer: @purge_cust, actor: 'ur_colonel_pub').call
@pr_events = AE.recent(2)
[
  @pr.status,
  Onetime::Customer.load(@purge_cust.objid).nil?,
  AE.count,
  @pr_events.map { |event| event['verb'] },
  @pr_events.map { |event| event['target'] },
]
#=> [:success, true, 2, ["customer.purge", "session.revoke_all"], [@purge_extid, @purge_extid]]

## Purge of a customer whose extid index entry has DRIFTED still revokes the
## live session: Purge hands the op the record it holds, so the blob is gone,
## the customer is destroyed, and session.revoke_all records blobs_deleted 1
## at the extid. (With `custid: extid` the re-resolution misses, the revoke
## degrades to 0 and the destroy leaves the blob live behind a deleted customer.)
AE.events.clear
@pd_pre = [
  Onetime::Customer.load_by_extid_or_email(@purge_drift_extid).nil?,                       # drift is real
  Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, @purge_drift_sid).nil?, # blob is live
]
@pd        = Auth::Operations::Customers::Purge.new(customer: @purge_drift, actor: 'ur_colonel_pub').call
@pd_revoke = AE.recent(2).find { |event| event['verb'] == 'session.revoke_all' }
[
  @pd_pre,
  @pd.status,
  Onetime::Customer.load(@purge_drift.objid).nil?,
  Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, @purge_drift_sid).nil?,
  @pd_revoke['target'],
  @pd_revoke['detail']['blobs_deleted'],
]
#=> [[true, false], :success, true, true, @purge_drift_extid, 1]

# ---- Doctor -----------------------------------------------------------

## Doctor reports no issues for a healthy customer
Auth::Operations::Customers::Doctor.new(customer: @doc_healthy).call.issues
#=> []

## Doctor detects an invalid-role integrity issue (role outside its valid set)
Auth::Operations::Customers::Doctor.new(customer: @doc_bad).call.issues.map { |i| i[:check] }
#=> [:role_invalid]

## Doctor repair with an actor audits once per repaired customer
AE.events.clear
@doc_rep_report = Auth::Operations::Customers::Doctor.new(
  customer: @doc_repair, repair: true, actor: 'ur_colonel_pub'
).call
[@doc_rep_report.repaired.any? { |r| r[:action] == :verified_by_set }, AE.count, AE.recent(1).first['verb']]
#=> [true, 1, "customer.doctor_repair"]

## Doctor audit-only run (no repair) does not audit
AE.events.clear
Auth::Operations::Customers::Doctor.new(customer: @doc_bad, repair: false).call
AE.count
#=> 0

# Cleanup
AE.events.clear
Familia.dbclient.del("session:#{@purge_drift_sid}")
Onetime::SessionMetadata.load(@purge_drift_sid)&.destroy! rescue nil
[@list_customers, @show_cust, @role_cust, @ver_cust, @doc_healthy, @doc_bad, @doc_repair, @purge_drift].flatten.each do |c|
  c.destroy! rescue nil
end
