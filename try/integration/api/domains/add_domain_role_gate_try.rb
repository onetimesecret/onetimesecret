# try/integration/api/domains/add_domain_role_gate_try.rb
#
# frozen_string_literal: true

#
# Integration tests for PR #3033 §2: only org owners and admins may add a
# custom domain. Drives POST /api/domains/add through the full Otto router
# (sessionauth) so the gate is exercised end-to-end, not via Logic#raise_concerns
# alone (covered by try/unit/logic/domains/add_domain_try.rb).
#
# Coverage:
# 1. Owner of the active org → 200
# 2. Admin of the active org → 200
# 3. Member of the active org → 403 (Onetime::Forbidden, otto_hooks maps to 403)
# 4. Member rejected via explicit org_id param (gate runs against target_org,
#    not the session's active org)
# 5. Non-member with explicit org_id → existing 422 FormError (regression
#    guard: resolution-stage check still fires BEFORE the role check)
# 6. Colonel with only a `member` membership → 200 (colonel: true bypass in
#    verify_one_of_roles!, gated on verified email)
# 7. Rejection message resolves the EN locale entry (not the helper's
#    fallback default), confirming the new i18n key is loaded

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def post(*args); @test.post(*args); end
def get(*args);  @test.get(*args);  end
def last_response; @test.last_response; end

# Setup: unique identifiers per run
@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# Owner of @org (created the org → owner role implicitly)
@owner = Onetime::Customer.create!(email: "role_gate_owner_#{@ts}_#{@entropy}@test.com")
@owner_session = {
  'authenticated' => true,
  'external_id'   => @owner.extid,
  'email'         => @owner.email,
}

# Admin and member memberships in the same org
@admin_user = Onetime::Customer.create!(email: "role_gate_admin_#{@ts}_#{@entropy}@test.com")
@admin_session = {
  'authenticated' => true,
  'external_id'   => @admin_user.extid,
  'email'         => @admin_user.email,
}

@member_user = Onetime::Customer.create!(email: "role_gate_member_#{@ts}_#{@entropy}@test.com")
@member_session = {
  'authenticated' => true,
  'external_id'   => @member_user.extid,
  'email'         => @member_user.email,
}

@org = Onetime::Organization.create!("Role Gate Org #{@ts}", @owner, "role_gate_org_#{@ts}@test.com")
@admin_membership  = @org.add_members_instance(@admin_user,  through_attrs: { role: 'admin'  })
@member_membership = @org.add_members_instance(@member_user, through_attrs: { role: 'member' })

## Setup verification — fixtures wired as expected
[
  @org.owner?(@owner),
  @org.member?(@admin_user),
  @org.member?(@member_user),
  @admin_membership.role,
  @member_membership.role,
]
#=> [true, true, true, 'admin', 'member']

## TEST 1: Owner POST /api/domains/add → 200 (control case)
@owner_domain = "owner-#{@ts}-#{@entropy}.example.com"
post '/api/domains/add',
  { 'domain' => @owner_domain },
  {
    'rack.session' => @owner_session.merge('organization_id' => @org.objid),
    'HTTP_ACCEPT'  => 'application/json',
  }
last_response.status
#=> 200

## TEST 1b: Owner domain landed in the org
@org.list_domains.map(&:display_domain).include?(@owner_domain)
#=> true

## TEST 2: Admin POST /api/domains/add → 200
@admin_domain = "admin-#{@ts}-#{@entropy}.example.com"
post '/api/domains/add',
  { 'domain' => @admin_domain },
  {
    'rack.session' => @admin_session.merge('organization_id' => @org.objid),
    'HTTP_ACCEPT'  => 'application/json',
  }
last_response.status
#=> 200

## TEST 2b: Admin domain also landed in the org
@org.list_domains.map(&:display_domain).include?(@admin_domain)
#=> true

## TEST 3: Member POST /api/domains/add → 403 (Onetime::Forbidden via otto_hooks)
@member_domain = "member-#{@ts}-#{@entropy}.example.com"
post '/api/domains/add',
  { 'domain' => @member_domain },
  {
    'rack.session' => @member_session.merge('organization_id' => @org.objid),
    'HTTP_ACCEPT'  => 'application/json',
  }
last_response.status
#=> 403

## TEST 3b: No domain was created for the rejected member request
@org.list_domains.map(&:display_domain).include?(@member_domain)
#=> false

## TEST 3c: Rejection message resolves the EN locale entry, not the helper's
## fallback default. The locale text is "...can add custom domains" while the
## default fallback is "...can perform this action" — so a hit on the
## domain-specific phrase confirms api.domains.errors.add_admin_required was
## actually loaded (regression guard against a missing or renamed key).
last_response.body.include?('add custom domains')
#=> true

## TEST 4: Member rejected via explicit org_id (gate runs against target_org)
# Add member to a second org so resolve_target_organization succeeds; the
# admin gate must still fail because the role is 'member' in @org2.
@org2 = Onetime::Organization.create!("Role Gate Org 2 #{@ts}", @owner, "role_gate_org2_#{@ts}@test.com")
@org2_member_membership = @org2.add_members_instance(@member_user, through_attrs: { role: 'member' })
@member_explicit_domain = "member-explicit-#{@ts}-#{@entropy}.example.com"
post '/api/domains/add',
  { 'domain' => @member_explicit_domain, 'org_id' => @org2.objid },
  {
    'rack.session' => @member_session.merge('organization_id' => @org.objid),
    'HTTP_ACCEPT'  => 'application/json',
  }
last_response.status
#=> 403

## TEST 4b: Explicit-org rejection did not create the domain
@org2.list_domains.map(&:display_domain).include?(@member_explicit_domain)
#=> false

## TEST 5: Non-member with explicit org_id → existing 422 FormError
# Regression guard: the resolution-stage membership check still rejects
# *before* the role gate runs, so the user sees the existing "not found
# or access denied" message rather than the new admin-required one
# (otto_hooks maps FormError → 422).
@nonmember_org = Onetime::Organization.create!("Nonmember Org #{@ts}", @owner, "nonmember_org_#{@ts}@test.com")
@nonmember_domain = "nonmember-#{@ts}-#{@entropy}.example.com"
post '/api/domains/add',
  { 'domain' => @nonmember_domain, 'org_id' => @nonmember_org.objid },
  {
    'rack.session' => @member_session.merge('organization_id' => @org.objid),
    'HTTP_ACCEPT'  => 'application/json',
  }
[last_response.status, last_response.body.include?('access denied') || last_response.body.include?('not found')]
#=> [422, true]

## TEST 6: Colonel with only a `member` membership → 200
# verify_organization_admin uses verify_one_of_roles!(colonel: true, ...) which
# bypasses every role check for colonels. has_system_role?('colonel') also
# requires cust.verified? — set both so the bypass actually fires.
@colonel_user = Onetime::Customer.create!(email: "role_gate_colonel_#{@ts}_#{@entropy}@test.com")
@colonel_user.role = 'colonel'
@colonel_user.verified = 'true'
@colonel_user.save
@colonel_session = {
  'authenticated' => true,
  'external_id'   => @colonel_user.extid,
  'email'         => @colonel_user.email,
}
@colonel_membership = @org.add_members_instance(@colonel_user, through_attrs: { role: 'member' })
@colonel_domain = "colonel-#{@ts}-#{@entropy}.example.com"
post '/api/domains/add',
  { 'domain' => @colonel_domain },
  {
    'rack.session' => @colonel_session.merge('organization_id' => @org.objid),
    'HTTP_ACCEPT'  => 'application/json',
  }
last_response.status
#=> 200

## TEST 6b: Colonel-added domain landed in the org
@org.list_domains.map(&:display_domain).include?(@colonel_domain)
#=> true

# Teardown
@org.list_domains.each(&:destroy!)
@org2.list_domains.each(&:destroy!)
@nonmember_org.list_domains.each(&:destroy!)
@admin_membership.destroy! if @admin_membership&.exists?
@member_membership.destroy! if @member_membership&.exists?
@org2_member_membership.destroy! if @org2_member_membership&.exists?
@colonel_membership.destroy! if @colonel_membership&.exists?
@org.destroy!
@org2.destroy!
@nonmember_org.destroy!
@admin_user.destroy!
@member_user.destroy!
@colonel_user.destroy!
@owner.destroy!
