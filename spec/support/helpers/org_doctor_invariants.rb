# spec/support/helpers/org_doctor_invariants.rb
#
# frozen_string_literal: true

# The `bin/ots org doctor` integrity checks, as a reusable assertion for
# specs of any operation that produces or repairs an organization
# (`Onetime::Operations::Org::Create`, `…::TransferOwnership`, the doctor's own
# repair paths).
#
# WHY THIS EXISTS: "the org this verb produced is healthy" is the real
# post-condition of those ops, and it is only provable against a REAL datastore
# — the owner membership is a Familia through-model that materializes on write,
# so a mocked org can satisfy every check vacuously.
#
# The checks are a faithful port of lib/onetime/cli/org/doctor_command.rb
# (check_owner_exists / check_owner_in_members / check_members_exist /
# check_membership_role_sync / check_has_members / check_unique_indexes). If
# that file changes, change this in lockstep — a spec that silently stops
# asserting an invariant is worse than no spec.
#
# Check 6 is ported in its NARROW form: "the org holds its own entry in every
# class-level unique index". The doctor additionally distinguishes a stale
# entry from a live duplicate to decide repairability; an op-produced org has
# no business being in either state, so any non-self holder is one failure line
# here (#4205).
#
# The index list is read from the doctor's own UNIQUE_INDEXES rather than
# copied, so a sixth index added there is asserted here without a second edit.
module OrgDoctorInvariants
  # Run all six checks against a live org.
  #
  # @param org [Onetime::Organization] a persisted org (NOT a double)
  # @return [Array<String>] one human-readable line per failed check; empty when
  #   the org is healthy. Returning strings (rather than booleans) means a
  #   failing expectation names the invariant that broke.
  def org_doctor_issues(org)
    issues = []

    owner_id = org.owner_id.to_s
    owner    = owner_id.empty? ? nil : Onetime::Customer.load(owner_id)

    # CHECK 1 (CRITICAL): owner_id points to an existing customer.
    if owner_id.empty?
      issues << 'check 1 (owner_exists): owner_id is blank'
    elsif owner.nil?
      issues << "check 1 (owner_exists): owner_id '#{owner_id}' points to no customer"
    end

    # CHECK 2 (HIGH): the owner is in the members sorted set.
    if owner && !org.member?(owner)
      issues << "check 2 (owner_in_members): owner '#{owner_id}' not in members set"
    end

    # CHECK 3 (MEDIUM): every member has a backing customer object.
    stale = org.members.to_a.reject { |id| Familia.dbclient.exists?("customer:#{id}:object") }
    issues << "check 3 (members_exist): #{stale.size} stale member(s): #{stale.inspect}" if stale.any?

    # CHECK 4 (WARNING): the only membership with role 'owner' is owner_id.
    mismatches = org.members.to_a.select do |member_id|
      membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, member_id)
      membership && membership.role == 'owner' && member_id != owner_id
    end
    if mismatches.any?
      issues << "check 4 (membership_role_sync): role:'owner' membership(s) != owner_id: #{mismatches.inspect}"
    end

    # CHECK 5 (WARNING): at least one member.
    issues << 'check 5 (has_members): organization has no members' unless org.member_count.positive?

    # CHECK 6: every class-level unique index points back here. Most orgs only
    # carry contact_email, so most of these are no-ops — but an org that
    # carries an indexed field and does NOT hold its entry cannot complete
    # another full save, so an op that leaves one behind has failed.
    issues.concat(unique_index_issues(org))

    issues
  end

  # @return [Array<String>] one failure line per index that does not point here.
  def unique_index_issues(org)
    org_unique_index_specs.filter_map do |spec|
      next unless org.respond_to?(spec[:field])
      next unless Onetime::Organization.respond_to?(spec[:index])

      # Verbatim, matching how Familia keys the index field (see the doctor's
      # check_unique_index).
      value = org.public_send(spec[:field]).to_s
      next if value.strip.empty?

      holder = strip_legacy_index_value(
        Onetime::Organization.public_send(spec[:index])[value].to_s
      )
      next if holder == org.objid.to_s

      shown  = spec[:email] ? OT::Utils.obscure_email(value) : value
      reason = holder.empty? ? 'no index entry (field written without claiming it)' : "index entry holds '#{holder}'"
      "check 6 (#{spec[:index]}): #{spec[:field]} '#{shown}' #{reason}"
    end
  end

  # The doctor's own list, so the two cannot drift. Falls back to the one index
  # this helper was born asserting if the command is not loaded in this spec
  # run — a missing constant must not silently drop the invariant.
  def org_unique_index_specs
    return Onetime::CLI::OrgDoctorCommand::UNIQUE_INDEXES if defined?(Onetime::CLI::OrgDoctorCommand::UNIQUE_INDEXES)

    [{ field: :stripe_customer_id, index: :stripe_customer_id_index }]
  end

  # Familia 2.9 stored unique-index values JSON-encoded ("\"on1a...\""), 2.10+
  # raw. An unstripped value never equals a bare objid, so on a dataset still
  # carrying the legacy form this helper would fail every billed org for a
  # check-6 violation that is not one. Mirrors the doctor's
  # OrgDoctorCommand#index_value and Familia's own read path; storage is
  # rewritten by the 20260606_01_unique_index_json_to_raw migration.
  def strip_legacy_index_value(value)
    value = value.to_s
    return value unless Familia.respond_to?(:legacy_json_encoded?)
    return value unless Familia.legacy_json_encoded?(value)

    value[1..-2].to_s
  end

  # The owner's membership record, for assertions the doctor does not make but
  # which the create/transfer ops depend on (active? and role).
  #
  # @return [Onetime::OrganizationMembership, nil]
  def org_owner_membership(org, customer)
    Onetime::OrganizationMembership.find_by_org_customer(org.objid, customer.objid)
  end
end

RSpec.configure do |config|
  config.include OrgDoctorInvariants
end
