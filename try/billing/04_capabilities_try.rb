require_relative '../support/test_helpers'

# Billing Capabilities System Tests
#
# Tests capability-based authorization system including:
# - Organization capability checking (can?)
# - Capability listing from plan definitions
# - Limit checking (limit_for, at_limit?)
# - Upgrade path recommendations
# - Plan version support (legacy vs current)
# - Fail-safe behavior (unknown plans)

## Setup: Load models and billing modules
require 'lib/onetime/models/organization'
require 'lib/onetime/billing/plan_definitions'

## Create test organizations with different plans

# Free plan organization
@free_org = Onetime::Organization.new(
  display_name: 'Free Org',
  owner_id: 'cust_test_001',
  contact_email: 'free@example.com',
  planid: 'free'
)
@free_org.save
@free_org.planid
#=> 'free'

# Identity Plus v1 organization
@identity_org = Onetime::Organization.new(
  display_name: 'Identity Org',
  owner_id: 'cust_test_002',
  contact_email: 'identity@example.com',
  planid: 'identity_v1'
)
@identity_org.save
@identity_org.planid
#=> 'identity_v1'

# Multi-Team v1 organization
@multi_org = Onetime::Organization.new(
  display_name: 'Multi Org',
  owner_id: 'cust_test_003',
  contact_email: 'multi@example.com',
  planid: 'multi_team_v1'
)
@multi_org.save
@multi_org.planid
#=> 'multi_team_v1'

# Legacy Identity v0 organization (grandfathered)
@legacy_org = Onetime::Organization.new(
  display_name: 'Legacy Org',
  owner_id: 'cust_test_004',
  contact_email: 'legacy@example.com',
  planid: 'identity_v0'
)
@legacy_org.save
@legacy_org.planid
#=> 'identity_v0'

## Test: Free plan capabilities
@free_org.capabilities.sort
#=> ["basic_sharing", "create_secrets", "view_metadata"]

## Test: Free plan can create secrets
@free_org.can?('create_secrets')
#=> true

## Test: Free plan cannot create teams
@free_org.can?('create_team')
#=> false

## Test: Free plan cannot access custom domains
@free_org.can?('custom_domains')
#=> false

## Test: Identity Plus v1 capabilities include team creation
@identity_org.can?('create_team')
#=> true

## Test: Identity Plus v1 has custom domains
@identity_org.can?('custom_domains')
#=> true

## Test: Identity Plus v1 does not have API access
@identity_org.can?('api_access')
#=> false

## Test: Identity Plus v1 does not have audit logs
@identity_org.can?('audit_logs')
#=> false

## Test: Multi-Team has all advanced features
@multi_org.can?('create_teams')
#=> true

@multi_org.can?('api_access')
#=> true

@multi_org.can?('audit_logs')
#=> true

@multi_org.can?('advanced_analytics')
#=> true

## Test: Legacy plan (v0) has limited capabilities
@legacy_org.can?('create_team')
#=> true

## Test: Legacy plan does NOT have custom domains
@legacy_org.can?('custom_domains')
#=> false

## Test: Limit checking - Free plan secret limit
@free_org.limit_for('secrets_per_day')
#=> 10

## Test: Limit checking - Free plan lifetime limit
@free_org.limit_for('secret_lifetime')
#=:> 7.days

## Test: Identity Plus teams limit
@identity_org.limit_for('teams')
#=> 1

## Test: Identity Plus members_per_team is unlimited
@identity_org.limit_for('members_per_team')
#=> Float::INFINITY

## Test: Multi-Team teams is unlimited
@multi_org.limit_for('teams')
#=> Float::INFINITY

## Test: Legacy plan has old member limit
@legacy_org.limit_for('members_per_team')
#=> 10

## Test: Unknown resource defaults to infinity for paid plans
@identity_org.limit_for('unknown_resource')
#=> Float::INFINITY

## Test: Unknown resource defaults to 0 for plans without definition
@unknown_org = Onetime::Organization.new(
  display_name: 'Unknown Plan',
  owner_id: 'cust_test_999',
  contact_email: 'unknown@example.com',
  planid: 'nonexistent_plan'
)
@unknown_org.limit_for('teams')
#=> 0

## Test: at_limit? check when at limit
@identity_org.at_limit?('teams', 1)
#=> true

## Test: at_limit? check when under limit
@identity_org.at_limit?('teams', 0)
#=> false

## Test: at_limit? never true for unlimited resources
@multi_org.at_limit?('teams', 999999)
#=> false

## Test: check_capability returns detailed response
@result = @free_org.check_capability('custom_domains')
@result[:allowed]
#=> false

@result[:upgrade_needed]
#=> true

@result[:capability]
#=> "custom_domains"

@result[:current_plan]
#=> "free"

## Test: check_capability includes upgrade path
@result[:upgrade_to]
#=> "identity_v1"

## Test: check_capability for allowed capability
@allowed_result = @identity_org.check_capability('custom_domains')
@allowed_result[:allowed]
#=> true

@allowed_result[:upgrade_needed]
#=> false

## Test: Upgrade path recommendation for free to custom_domains
Onetime::Billing.upgrade_path_for('custom_domains', 'free')
#=> "identity_v1"

## Test: Upgrade path for Identity to audit_logs
Onetime::Billing.upgrade_path_for('audit_logs', 'identity_v1')
#=> "multi_team_v1"

## Test: Upgrade path for capability not available returns nil
Onetime::Billing.upgrade_path_for('nonexistent_capability', 'free')
#=> nil

## Test: Plan name formatting
Onetime::Billing.plan_name('free')
#=> "Free"

Onetime::Billing.plan_name('identity_v1')
#=> "Identity Plus"

Onetime::Billing.plan_name('multi_team_v1')
#=> "Multi-Team"

## Test: Legacy plan detection
Onetime::Billing.legacy_plan?('identity_v0')
#=> true

Onetime::Billing.legacy_plan?('identity_v1')
#=> false

## Test: Available plans excludes legacy
Onetime::Billing.available_plans.include?('identity_v1')
#=> true

Onetime::Billing.available_plans.include?('identity_v0')
#=> false

## Test: Capability categories defined
Onetime::Billing::CAPABILITY_CATEGORIES[:core].class
#=> Array

Onetime::Billing::CAPABILITY_CATEGORIES[:core].include?('create_secrets')
#=> true

## Test: Fail-safe for nil planid
@no_plan_org = Onetime::Organization.new(
  display_name: 'No Plan',
  owner_id: 'cust_test_888',
  contact_email: 'noplan@example.com'
)
@no_plan_org.planid = nil
@no_plan_org.capabilities
#=> []

@no_plan_org.can?('create_secrets')
#=> false

@no_plan_org.limit_for('teams')
#=> 0

## Test: Fail-safe for empty string planid
@empty_plan_org = Onetime::Organization.new(
  display_name: 'Empty Plan',
  owner_id: 'cust_test_777',
  contact_email: 'empty@example.com'
)
@empty_plan_org.planid = ''
@empty_plan_org.capabilities
#=> []

## Test: Organization defaults to 'free' plan on init
@new_org = Onetime::Organization.new(
  display_name: 'New Org',
  owner_id: 'cust_test_555',
  contact_email: 'new@example.com'
)
@new_org.planid
#=> 'free'

@new_org.can?('create_secrets')
#=> true

## Teardown: Clean up test organizations
[@free_org, @identity_org, @multi_org, @legacy_org, @unknown_org, @no_plan_org, @empty_plan_org, @new_org].each do |org|
  org&.destroy! rescue nil
end
true
#=> true
