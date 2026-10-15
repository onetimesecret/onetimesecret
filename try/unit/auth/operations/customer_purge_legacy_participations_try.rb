# frozen_string_literal: true

# R1-R3: datastore regressions for legacy, unquoted customer participations.
# Run only through:
# tests/lanes/run --only try/unit/auth/operations/customer_purge_legacy_participations_try.rb
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'web/auth/operations/customers'
require 'onetime/operations/org/delete'

module CustomerPurgeLegacyParticipationsTry
  module_function

  # Keep cleanup independent of the assertion outcome, including the pre-fix
  # partial purge that deletes the organization but leaves its customer alive.
  def with_customer
    customer = Onetime::Customer.create!(email: generate_unique_test_email('legacy_participation'))
    organizations = []
    yield customer, organizations
  ensure
    begin
      organizations&.reverse_each do |org|
        org.destroy! if org.exists?
      end
    ensure
      customer.destroy! if customer&.exists?
    end
  end

  def organization(customer, organizations, default: true)
    org = Onetime::Organization.create!(
      'Legacy participation regression', customer, nil,
      is_default: default, planid: 'free_v1',
    )
    organizations << org
    org
  end

  # Seed bytes directly: using DataType#add for the raw variant would silently
  # JSON-encode it and turn the regression into another canonical happy path.
  def seed(customer, key, shape)
    set = customer.participations
    encoded = set.serialize_value(key)
    set.dbclient.srem(set.dbkey, encoded, key)
    values = case shape
             when :canonical then [encoded]
             when :raw then [key]
             when :mixed then [encoded, key]
             else raise ArgumentError, "Unknown storage shape: #{shape}"
             end
    set.dbclient.sadd(set.dbkey, values)
    values.sort
  end

  def purge(customer)
    Auth::Operations::Customers::Purge.new(
      customer: customer, actor: 'cli', reason: 'legacy participation regression',
    ).call
  end

  def purge_case(shape)
    with_customer do |customer, organizations|
      org = organization(customer, organizations)
      key = org.members.dbkey
      membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, customer.objid)
      expected_bytes = seed(customer, key, shape)
      seeded = customer.participations.membersraw.sort == expected_bytes
      eligible = Auth::Operations::Customers::PurgePreflight.new(customer: customer).call.executable?
      result = purge(customer)
      [seeded, eligible, result.status, result.stage, result.blockers,
       result.completed_stages.include?(:delete_organization),
       customer.exists?, org.exists?, membership.exists?, customer.participations.membersraw]
    end
  end

  def delete_case(shape)
    with_customer do |customer, organizations|
      deleted = organization(customer, organizations, default: false)
      keeper = organization(customer, organizations)
      customer.default_org_id = keeper.objid
      customer.save
      membership = Onetime::OrganizationMembership.find_by_org_customer(deleted.objid, customer.objid)
      keeper_membership = Onetime::OrganizationMembership.find_by_org_customer(keeper.objid, customer.objid)
      seed(customer, deleted.members.dbkey, shape)
      # Preserve both physical representations of the unrelated participation.
      keeper_bytes = seed(customer, keeper.members.dbkey, :mixed)
      result = Onetime::Operations::Org::Delete.new(
        org: deleted, actor: 'cli', dry_run: false, reason: 'legacy participation regression',
      ).call
      [result.status, deleted.exists?, membership.exists?, customer.exists?,
       keeper.exists?, keeper.member?(customer), keeper_membership.exists?,
       customer.participations.membersraw.sort == keeper_bytes,
       Onetime::Customer.load(customer.objid).default_org_id == keeper.objid]
    end
  end

  # Reproduce the previous partial purge: canonical organization teardown has
  # finished, but a legacy reverse-index entry survives on the customer.
  def previous_partial(customer, organizations, shape, prefix: 'organization')
    org = organization(customer, organizations)
    plan = Auth::Operations::Customers::PurgePreflight.new(customer: customer).call
    action = plan.actions.find { |entry| entry.type == :delete_organization }
    result = Onetime::Operations::Org::Delete.new(
      org: org, actor: 'cli', dry_run: false,
      account_purge_context: action.account_purge_context,
    ).call
    raise "Fixture teardown failed: #{result.status}" unless result.status == :success

    key = "#{prefix}:#{org.objid}:members"
    seed(customer, key, shape)
    [org, key]
  end

  def retry_case(shape, prefix: 'organization')
    with_customer do |customer, organizations|
      org, key = previous_partial(customer, organizations, shape, prefix: prefix)
      before = customer.participations.membersraw.sort
      plan = Auth::Operations::Customers::PurgePreflight.new(customer: customer).call
      action = plan.actions.first
      planned = plan.executable? && plan.actions.size == 1 &&
        action.type == :remove_stale_participation && action.reference == key &&
        action.organization.objid == org.objid && action.org_id == org.objid && action.role == ''
      unchanged = customer.participations.membersraw.sort == before
      result = purge(customer)
      [planned, unchanged, result.status, result.stage, result.blockers,
       result.actions == [action.public_detail(status: :success)],
       customer.exists?, org.exists?, customer.participations.membersraw]
    end
  end

  def dependency_case(kind)
    with_customer do |customer, organizations|
      org, reference = previous_partial(customer, organizations, :mixed)
      redis = Onetime::Organization.dbclient
      key = case kind
            when :members then "organization:#{org.objid}:members"
            when :invitation then "org:#{org.objid}:pending_invitations"
            when :membership then "#{Onetime::OrganizationMembership.prefix}:organization:#{org.objid}:survivor:history"
            end
      redis.set(key, 'retained dependency')
      before = customer.participations.membersraw.sort
      begin
        result = purge(customer)
        [result.status, result.actions.empty?, customer.exists?,
         customer.participations.membersraw.sort == before,
         redis.get(key) == 'retained dependency',
         result.blockers.any? { |entry| entry[:code] == :orphan_organization_dependencies_remain }]
      ensure
        redis.del(key)
      end
    end
  end

  def untrack_case(shape)
    with_customer do |customer, organizations|
      removed = organization(customer, organizations, default: false)
      keeper = organization(customer, organizations)
      key = removed.members.dbkey
      seed(customer, key, shape)
      keeper_bytes = seed(customer, keeper.members.dbkey, :mixed)
      first = customer.untrack_participation_in(key)
      after_first = customer.participations.membersraw.sort
      second = customer.untrack_participation_in(key)
      [first, second, after_first == keeper_bytes,
       customer.participations.membersraw.sort == keeper_bytes,
       keeper.exists?, keeper.member?(customer)]
    end
  end
end

## R1: canonical-only participation permits complete single-free-workspace purge
CustomerPurgeLegacyParticipationsTry.purge_case(:canonical)
#=> [true, true, :success, :complete, [], true, false, false, false, []]

## R1: raw-only participation permits complete single-free-workspace purge
CustomerPurgeLegacyParticipationsTry.purge_case(:raw)
#=> [true, true, :success, :complete, [], true, false, false, false, []]

## R1: mixed participation permits complete single-free-workspace purge
CustomerPurgeLegacyParticipationsTry.purge_case(:mixed)
#=> [true, true, :success, :complete, [], true, false, false, false, []]

## R2: standalone deletion removes canonical participation and preserves the other org
CustomerPurgeLegacyParticipationsTry.delete_case(:canonical)
#=> [:success, false, false, true, true, true, true, true, true]

## R2: standalone deletion removes raw participation and preserves the other org
CustomerPurgeLegacyParticipationsTry.delete_case(:raw)
#=> [:success, false, false, true, true, true, true, true, true]

## R2: standalone deletion removes both encodings and preserves the other org
CustomerPurgeLegacyParticipationsTry.delete_case(:mixed)
#=> [:success, false, false, true, true, true, true, true, true]

## R3: doctor detects a raw orphan without mutating it
@doctor_baseline = CustomerPurgeLegacyParticipationsTry.with_customer do |customer, organizations|
  CustomerPurgeLegacyParticipationsTry.organization(customer, organizations)
  orphan_id = SecureRandom.uuid
  key = "organization:#{orphan_id}:members"
  CustomerPurgeLegacyParticipationsTry.seed(customer, key, :raw)
  before = customer.participations.membersraw.sort
  report = Auth::Operations::Customers::Doctor.new(customer: customer).call
  [report.issues.any? { |issue| issue[:check] == :org_membership_desync && issue[:org_objid] == orphan_id },
   report.repaired.empty?, customer.participations.membersraw.sort == before,
   Auth::Operations::Customers::PurgePreflight.new(customer: customer).call.actions.any? do |action|
     action.type == :remove_stale_participation && action.reference == key
   end]
end
@doctor_baseline
#=> [true, true, true, true]

## R3: doctor repair removes the raw orphan before reporting it repaired and allows purge
CustomerPurgeLegacyParticipationsTry.with_customer do |customer, organizations|
  org = CustomerPurgeLegacyParticipationsTry.organization(customer, organizations)
  keeper_bytes = customer.participations.membersraw.sort
  orphan_id = SecureRandom.uuid
  key = "organization:#{orphan_id}:members"
  CustomerPurgeLegacyParticipationsTry.seed(customer, key, :raw)
  report = Auth::Operations::Customers::Doctor.new(customer: customer, repair: true, actor: 'cli').call
  repaired = report.repaired.any? { |entry| entry[:action] == :stale_org_removed && entry[:org_objid] == orphan_id }
  raw_clean = customer.participations.membersraw.sort == keeper_bytes
  recheck = Auth::Operations::Customers::Doctor.new(customer: customer).call
  clean_recheck = recheck.issues.none? { |issue| issue[:check] == :org_membership_desync && issue[:org_objid] == orphan_id }
  second_repair = Auth::Operations::Customers::Doctor.new(customer: customer, repair: true, actor: 'cli').call
  no_repeat_repair = second_repair.repaired.none? { |entry| entry[:action] == :stale_org_removed && entry[:org_objid] == orphan_id }
  result = CustomerPurgeLegacyParticipationsTry.purge(customer)
  [repaired, raw_clean, clean_recheck, no_repeat_repair, result.status, result.stage,
   result.blockers, customer.exists?, org.exists?, customer.participations.membersraw]
end
#=> [true, true, true, true, :success, :complete, [], false, false, []]

## R3: a silent failed removal raises instead of returning a repaired doctor report
CustomerPurgeLegacyParticipationsTry.with_customer do |customer, organizations|
  CustomerPurgeLegacyParticipationsTry.organization(customer, organizations)
  key = "organization:#{SecureRandom.uuid}:members"
  CustomerPurgeLegacyParticipationsTry.seed(customer, key, :raw)
  before = customer.participations.membersraw.sort
  report = nil
  failure = nil
  # Inject failure only on this fixture; all discovery and verification reads
  # still use the real datastore. Remove the override before fixture cleanup.
  customer.define_singleton_method(:untrack_participation_in) { |_collection_key| 0 }
  begin
    report = Auth::Operations::Customers::Doctor.new(customer: customer, repair: true).call
  rescue Onetime::Problem => ex
    failure = ex
  ensure
    customer.singleton_class.remove_method(:untrack_participation_in)
  end
  [report.nil?, failure&.message == "Stale participation cleanup failed: #{key}",
   customer.participations.membersraw.sort == before,
   Auth::Operations::Customers::PurgePreflight.new(customer: customer).call.actions.any? do |action|
     action.type == :remove_stale_participation && action.reference == key
   end]
end
#=> [true, true, true, true]

## Retry completes a previous partial purge with a canonical orphan without doctor
CustomerPurgeLegacyParticipationsTry.retry_case(:canonical)
#=> [true, true, :success, :complete, [], true, false, false, []]

## Retry completes a previous partial purge with a raw orphan without doctor
CustomerPurgeLegacyParticipationsTry.retry_case(:raw)
#=> [true, true, :success, :complete, [], true, false, false, []]

## Retry completes a previous partial purge with mixed orphan encodings without doctor
CustomerPurgeLegacyParticipationsTry.retry_case(:mixed)
#=> [true, true, :success, :complete, [], true, false, false, []]

## Retry recognizes the legacy org prefix in both physical encodings
CustomerPurgeLegacyParticipationsTry.retry_case(:mixed, prefix: 'org')
#=> [true, true, :success, :complete, [], true, false, false, []]

## Orphan member data refuses cleanup and preserves customer and participation bytes
CustomerPurgeLegacyParticipationsTry.dependency_case(:members)
#=> [:refused, true, true, true, true, true]

## Orphan invitation data under the legacy prefix refuses cleanup without mutation
CustomerPurgeLegacyParticipationsTry.dependency_case(:invitation)
#=> [:refused, true, true, true, true, true]

## Orphan through-model subkeys refuse cleanup even without a membership object
CustomerPurgeLegacyParticipationsTry.dependency_case(:membership)
#=> [:refused, true, true, true, true, true]

## A silent no-op cleanup is partial, preserves the orphan, and can retry without doctor
CustomerPurgeLegacyParticipationsTry.with_customer do |customer, organizations|
  org, key = CustomerPurgeLegacyParticipationsTry.previous_partial(customer, organizations, :mixed)
  before = customer.participations.membersraw.sort
  customer.define_singleton_method(:untrack_participation_in) { |_reference| 0 }
  begin
    failed = CustomerPurgeLegacyParticipationsTry.purge(customer)
    preserved = customer.exists? && customer.participations.membersraw.sort == before
  ensure
    customer.singleton_class.remove_method(:untrack_participation_in)
  end
  markers = customer.purge_pending_organization_checks
  marker_retained = markers.to_a == [key]
  retried = CustomerPurgeLegacyParticipationsTry.purge(customer)
  [failed.status, failed.actions.empty?,
   failed.blockers.any? { |entry| entry[:code] == :stale_participation_cleanup_failed },
   preserved, marker_retained, retried.status, customer.exists?, org.exists?,
   customer.participations.membersraw, markers.dbclient.exists?(markers.dbkey)]
end
#=> [:partial, true, true, true, true, :success, false, false, [], false]

## PF07: fresh purge refuses late receipt dependencies after reverse-index cleanup
CustomerPurgeLegacyParticipationsTry.with_customer do |customer, organizations|
  org, reference = CustomerPurgeLegacyParticipationsTry.previous_partial(customer, organizations, :mixed)
  markers = customer.purge_pending_organization_checks
  receipt_key = org.receipts.dbkey
  redis = Onetime::Organization.dbclient
  original = customer.method(:untrack_participation_in)
  customer.define_singleton_method(:untrack_participation_in) do |key|
    removed = original.call(key)
    redis.zadd(receipt_key, 1, 'late-receipt')
    removed
  end
  begin
    first = CustomerPurgeLegacyParticipationsTry.purge(customer)
    first_preserved = customer.exists? && customer.participations.to_a.empty? && markers.to_a == [reference]
    reloaded = Onetime::Customer.load(customer.objid)
    second = CustomerPurgeLegacyParticipationsTry.purge(reloaded)
    second_preserved = reloaded.exists? && reloaded.participations.to_a.empty? &&
      reloaded.purge_pending_organization_checks.to_a == [reference] &&
      redis.zrange(receipt_key, 0, -1) == ['late-receipt']
    redis.del(receipt_key)
    plan = Auth::Operations::Customers::PurgePreflight.new(customer: reloaded).call
    marker_only = plan.executable? && plan.actions.empty? && markers.to_a == [reference]
    third = CustomerPurgeLegacyParticipationsTry.purge(reloaded)
    [first.status, first.actions.map { |action| action[:type] }, first_preserved,
     second.status, second.actions.empty?,
     second.blockers.any? { |blocker| blocker[:code] == :orphan_organization_dependencies_remain },
     second_preserved, marker_only, third.status, third.actions.empty?,
     reloaded.exists?, markers.dbclient.exists?(markers.dbkey)]
  ensure
    customer.singleton_class.remove_method(:untrack_participation_in)
    redis.del(receipt_key)
  end
end
#=> [:partial, [:remove_stale_participation], true, :refused, true, true, true, true, :success, true, false, false]

## PF07: an untrack exception after removal leaves a durable marker until successful teardown
CustomerPurgeLegacyParticipationsTry.with_customer do |customer, organizations|
  org, reference = CustomerPurgeLegacyParticipationsTry.previous_partial(customer, organizations, :raw)
  markers = customer.purge_pending_organization_checks
  original = customer.method(:untrack_participation_in)
  failure = IOError.new('untrack response lost')
  customer.define_singleton_method(:untrack_participation_in) do |key|
    original.call(key)
    raise failure
  end
  raised = nil
  begin
    CustomerPurgeLegacyParticipationsTry.purge(customer)
  rescue IOError => ex
    raised = ex
  ensure
    customer.singleton_class.remove_method(:untrack_participation_in)
  end
  reloaded = Onetime::Customer.load(customer.objid)
  retained = reloaded.purge_pending_organization_checks.to_a == [reference]
  removed = reloaded.participations.to_a.empty?
  result = CustomerPurgeLegacyParticipationsTry.purge(reloaded)
  [raised.equal?(failure), retained, removed, result.status, result.actions.empty?,
   reloaded.exists?, markers.dbclient.exists?(markers.dbkey)]
end
#=> [true, true, true, :success, true, false, false]

## R1: canonical untracking is idempotent and preserves unrelated raw and canonical bytes
CustomerPurgeLegacyParticipationsTry.untrack_case(:canonical)
#=> [1, 0, true, true, true, true]

## R1: raw untracking is idempotent and preserves unrelated raw and canonical bytes
CustomerPurgeLegacyParticipationsTry.untrack_case(:raw)
#=> [1, 0, true, true, true, true]

## R1: mixed untracking removes both entries once without touching unrelated bytes
CustomerPurgeLegacyParticipationsTry.untrack_case(:mixed)
#=> [2, 0, true, true, true, true]
