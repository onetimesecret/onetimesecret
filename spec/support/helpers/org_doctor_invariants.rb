# spec/support/helpers/org_doctor_invariants.rb
#
# frozen_string_literal: true

# The five `bin/ots org doctor` integrity checks, as a reusable assertion for
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
# check_membership_role_sync / check_has_members). If that file changes, change
# this in lockstep — a spec that silently stops asserting an invariant is worse
# than no spec.
module OrgDoctorInvariants
  # Run all five checks against a live org.
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

    issues
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
