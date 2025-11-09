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
require 'apps/web/billing/models/plan_cache'

## Setup: Populate PlanCache with test data (replaces hardcoded PLAN_DEFINITIONS)
Billing::Models::PlanCache.clear_cache

## Free plan
Billing::Models::PlanCache.new(
  plan_id: 'free',
  tier: 'free',
  interval: 'month',
  region: 'us-east',
  capabilities: '["create_secrets", "basic_sharing", "view_metadata"]',
  limits: '{"secrets_per_day": 10, "secret_lifetime": 604800}'
).save

## Identity Plus v1
Billing::Models::PlanCache.new(
  plan_id: 'identity_v1',
  tier: 'single_team',
  interval: 'month',
  region: 'us-east',
  capabilities: '["create_secrets", "basic_sharing", "view_metadata", "create_team", "custom_domains", "priority_support", "extended_lifetime"]',
  limits: '{"teams": 1, "members_per_team": -1, "custom_domains": -1, "secret_lifetime": 2592000}'
).save

## Multi-Team v1
Billing::Models::PlanCache.new(
  plan_id: 'multi_team_v1',
  tier: 'multi_team',
  interval: 'month',
  region: 'us-east',
  capabilities: '["create_secrets", "basic_sharing", "view_metadata", "create_teams", "custom_domains", "api_access", "priority_support", "extended_lifetime", "audit_logs", "advanced_analytics"]',
  limits: '{"teams": -1, "members_per_team": -1, "custom_domains": -1, "api_rate_limit": 10000, "secret_lifetime": 7776000}'
).save

## Legacy Identity v0 (for testing legacy plan support)
Billing::Models::PlanCache.new(
  plan_id: 'identity_v0',
  tier: 'single_team',
  interval: 'month',
  region: 'us-east',
  capabilities: '["create_secrets", "basic_sharing", "view_metadata", "create_team", "priority_support"]',
  limits: '{"teams": 1, "members_per_team": 10, "secret_lifetime": 1209600}'
).save

## Create unique test ID suffix to avoid collisions
@test_suffix = Time.now.to_i.to_s[-6..-1]
@test_suffix.class
#=> String

## Create free plan organization
@free_org = Onetime::Organization.new(
  display_name: 'Free Org',
  owner_id: 'cust_test_001',
  contact_email: "free-#{@test_suffix}@example.com",
  planid: 'free'
)
@free_org.save
@free_org.planid
#=> 'free'

## Create Identity Plus v1 organization
@identity_org = Onetime::Organization.new(
  display_name: 'Identity Org',
  owner_id: 'cust_test_002',
  contact_email: "identity-#{@test_suffix}@example.com",
  planid: 'identity_v1'
)
@identity_org.save
@identity_org.planid
#=> 'identity_v1'

## Create Multi-Team v1 organization
@multi_org = Onetime::Organization.new(
  display_name: 'Multi Org',
  owner_id: 'cust_test_003',
  contact_email: "multi-#{@test_suffix}@example.com",
  planid: 'multi_team_v1'
)
@multi_org.save
@multi_org.planid
#=> 'multi_team_v1'

## Create Legacy Identity v0 organization (grandfathered)
@legacy_org = Onetime::Organization.new(
  display_name: 'Legacy Org',
  owner_id: 'cust_test_004',
  contact_email: "legacy-#{@test_suffix}@example.com",
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

## Test: Identity Plus v1 can create team
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

## Test: Multi-Team can create multiple teams
@multi_org.can?('create_teams')
#=> true

## Test: Multi-Team has API access
@multi_org.can?('api_access')
#=> true

## Test: Multi-Team has audit logs
@multi_org.can?('audit_logs')
#=> true

## Test: Multi-Team has advanced analytics
@multi_org.can?('advanced_analytics')
#=> true

## Test: Legacy plan can create team
@legacy_org.can?('create_team')
#=> true

## Test: Legacy plan does NOT have custom domains
@legacy_org.can?('custom_domains')
#=> false

## Test: Free plan secret per day limit
@free_org.limit_for('secrets_per_day')
#=> 10

## Test: Free plan secret lifetime limit
@free_org.limit_for('secret_lifetime')
#=> 604800

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

## Test: Unknown resource defaults to 0 (fail-closed for security)
@identity_org.limit_for('unknown_resource')
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

## Test: check_capability returns not allowed for missing capability
@result = @free_org.check_capability('custom_domains')
@result[:allowed]
#=> false

## Test: check_capability shows upgrade needed
@result[:upgrade_needed]
#=> true

## Test: check_capability shows capability name
@result[:capability]
#=> "custom_domains"

## Test: check_capability shows current plan
@result[:current_plan]
#=> "free"

## Test: check_capability includes upgrade path
@result[:upgrade_to]
#=> "identity_v1"

## Test: check_capability for allowed capability shows allowed
@allowed_result = @identity_org.check_capability('custom_domains')
@allowed_result[:allowed]
#=> true

## Test: check_capability for allowed shows no upgrade needed
@allowed_result[:upgrade_needed]
#=> false

## Test: Upgrade path from free to custom_domains is identity
Onetime::Billing.upgrade_path_for('custom_domains', 'free')
#=> "identity_v1"

## Test: Upgrade path from Identity to audit_logs is multi_team
Onetime::Billing.upgrade_path_for('audit_logs', 'identity_v1')
#=> "multi_team_v1"

## Test: Upgrade path for nonexistent capability returns nil
Onetime::Billing.upgrade_path_for('nonexistent_capability', 'free')
#=> nil

## Test: Plan name for free
Onetime::Billing.plan_name('free')
#=> "Free"

## Test: Plan name for identity_v1
Onetime::Billing.plan_name('identity_v1')
#=> "Identity Plus"

## Test: Plan name for multi_team_v1
Onetime::Billing.plan_name('multi_team_v1')
#=> "Multi-Team"

## Test: Legacy plan detection for v0
Onetime::Billing.legacy_plan?('identity_v0')
#=> true

## Test: Legacy plan detection for v1
Onetime::Billing.legacy_plan?('identity_v1')
#=> false

## Test: Available plans includes identity_v1
Onetime::Billing.available_plans.include?('identity_v1')
#=> true

## Test: Available plans excludes legacy identity_v0
Onetime::Billing.available_plans.include?('identity_v0')
#=> false

## Test: Capability categories are defined
Onetime::Billing::CAPABILITY_CATEGORIES[:core].class
#=> Array

## Test: Core capabilities include create_secrets
Onetime::Billing::CAPABILITY_CATEGORIES[:core].include?('create_secrets')
#=> true

## Test: Fail-safe for nil planid returns empty capabilities
@no_plan_org = Onetime::Organization.new(
  display_name: 'No Plan',
  owner_id: 'cust_test_888',
  contact_email: "noplan-#{@test_suffix}@example.com"
)
@no_plan_org.planid = nil
@no_plan_org.capabilities
#=> []

## Test: Fail-safe for nil planid denies create_secrets
@no_plan_org.can?('create_secrets')
#=> false

## Test: Fail-safe for nil planid returns 0 limit
@no_plan_org.limit_for('teams')
#=> 0

## Test: Fail-safe for empty planid returns empty capabilities
@empty_plan_org = Onetime::Organization.new(
  display_name: 'Empty Plan',
  owner_id: 'cust_test_777',
  contact_email: "empty-#{@test_suffix}@example.com"
)
@empty_plan_org.planid = ''
@empty_plan_org.capabilities
#=> []

## Test: New organization defaults to free plan
@new_org = Onetime::Organization.new(
  display_name: 'New Org',
  owner_id: 'cust_test_555',
  contact_email: "new-#{@test_suffix}@example.com"
)
@new_org.planid
#=> 'free'

## Test: New organization can create secrets
@new_org.can?('create_secrets')
#=> true

## Teardown: Clean up test organizations
[@free_org, @identity_org, @multi_org, @legacy_org, @no_plan_org, @empty_plan_org, @new_org].each do |org|
  org&.destroy! rescue nil
end
true
#=> true
