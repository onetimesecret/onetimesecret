# Capability-Based UI Integration - Implementation Summary

## Overview

This implementation provides a complete capability-based UI integration system for the organization features, allowing the frontend to show/hide features based on organization capabilities rather than checking plan IDs directly.

## Files Created

### 1. Core Composable
- **`src/composables/useCapabilities.ts`** - Main composable for capability checking
  - `can(capability)` - Check if org has a capability
  - `limit(resource)` - Get limit for a resource
  - `upgradePath(capability)` - Get required plan for capability
  - `hasReachedLimit(resource, current)` - Check if limit reached
  - `capabilities` - Computed list of all capabilities
  - `planId` - Computed current plan ID

### 2. UI Component
- **`src/components/billing/UpgradePrompt.vue`** - Reusable upgrade prompt component
  - Props: `capability`, `upgradePlan`, `message`, `compact`
  - Displays amber-colored banner with upgrade CTA
  - Automatically routes to billing plans page with upgrade param

### 3. Test Suite
- **`src/components/billing/__tests__/UpgradePrompt.spec.ts`** - Unit tests for UpgradePrompt
  - Tests default messages
  - Tests custom messages
  - Tests compact mode
  - Tests URL generation

### 4. Documentation
- **`docs/capability-based-ui-integration.md`** - Comprehensive documentation
  - Key principles
  - Implementation overview
  - Usage examples
  - Anti-patterns to avoid
  - Backend API contract
  - Testing scenarios

## Files Modified

### 1. Type Definitions
**`src/types/organization.ts`**
- Added `CAPABILITIES` constant with all capability strings
- Added `Capability` type
- Added `OrganizationLimits` interface
- Extended `Organization` interface with `planid`, `capabilities`, `limits`
- Updated `organizationSchema` to validate new fields

### 2. State Management
**`src/stores/organizationStore.ts`**
- Added `fetchCapabilities(orgId)` method
- Fetches capabilities from `/api/billing/capabilities/:orgId`
- Updates organization and currentOrganization with capability data
- Gracefully handles errors (capabilities are optional enhancements)

### 3. UI Integration
**`src/views/teams/TeamsHub.vue`**
- Integrated capability checking for team creation
- Shows UpgradePrompt when capability missing
- Shows UpgradePrompt when team limit reached
- Hides "Create Team" button/tab when not allowed

**`src/views/account/settings/OrganizationSettings.vue`**
- Displays current capabilities in billing tab
- Shows formatted capability list with check icons
- Uses `formatCapability()` helper for user-friendly labels

### 4. Internationalization
**`src/locales/en.json`**
- Added `web.billing.upgrade` section:
  - `required` - "Upgrade Required"
  - `viewPlans` - "View Plans"
  - `needTeams` - Message for team capability
  - `needCustomDomains` - Message for domain capability
  - `needApiAccess` - Message for API capability
  - `needPrioritySupport` - Message for support capability
  - `needAuditLogs` - Message for audit log capability

## Key Features

### 1. Capability Checking
```typescript
const { can, limit, upgradePath } = useCapabilities(currentOrganization);

// Check capability
if (can(CAPABILITIES.CREATE_TEAMS)) {
  // Show feature
}

// Check limit
if (!hasReachedLimit('teams', teams.length)) {
  // Allow creation
}
```

### 2. Upgrade Prompts
```vue
<UpgradePrompt
  v-if="!can(CAPABILITIES.CREATE_TEAMS)"
  :capability="CAPABILITIES.CREATE_TEAMS"
  :upgrade-plan="upgradePath(CAPABILITIES.CREATE_TEAMS)"
  :message="t('web.billing.upgrade.needTeams')"
/>
```

### 3. Feature Display
```vue
<!-- Only show if capable -->
<button v-if="can(CAPABILITIES.CUSTOM_DOMAINS)">
  Add Domain
</button>

<!-- Show upgrade prompt if not capable -->
<UpgradePrompt v-else ... />
```

## Design Principles

### 1. Never Check Plan IDs
**Bad:** `v-if="org.planid === 'identity_v1'"`
**Good:** `v-if="can(CAPABILITIES.CUSTOM_DOMAINS)"`

### 2. Fail Safely
If capability data is missing or fails to load, features are hidden by default.

### 3. Clear Upgrade Paths
When a capability is missing, users see exactly what they need to do to unlock it.

### 4. Centralized Logic
All capability checking logic is in the composable, not scattered across components.

## Backend Integration

### Required API Endpoint
```
GET /api/billing/capabilities/:orgId
```

### Response Format
```json
{
  "planid": "multi_team_v1",
  "capabilities": [
    "create_secrets",
    "basic_sharing",
    "create_team",
    "create_teams",
    "api_access"
  ],
  "limits": {
    "teams": 5,
    "members_per_team": 10,
    "custom_domains": 0
  }
}
```

## Usage Examples

### Check Single Capability
```typescript
const canCreateDomains = can(CAPABILITIES.CUSTOM_DOMAINS);
```

### Check Multiple Capabilities
```typescript
const canCreateAnyTeam = can(CAPABILITIES.CREATE_TEAM) || can(CAPABILITIES.CREATE_TEAMS);
```

### Check Limit
```typescript
const teamLimit = limit('teams');
const atLimit = hasReachedLimit('teams', teams.value.length);
```

### Get Upgrade Plan
```typescript
const planNeeded = upgradePath(CAPABILITIES.API_ACCESS);
// Returns: "multi_team_v1"
```

### Display Capabilities
```vue
<div v-for="cap in capabilities" :key="cap">
  {{ formatCapability(cap) }}
</div>
```

## Testing

Run the UpgradePrompt tests:
```bash
pnpm test src/components/billing/__tests__/UpgradePrompt.spec.ts
```

## Next Steps

### For Frontend Integration
1. Apply capability checks to other features:
   - Custom domains management
   - API settings
   - Team member limits
   - Priority support access

2. Add capability indicators in plan comparison UI

3. Create billing plan selector that shows capabilities

### For Backend Implementation
1. Implement `/api/billing/capabilities/:orgId` endpoint
2. Map plan IDs to capabilities in backend
3. Calculate limits based on subscription
4. Return capabilities with organization data

### For Testing
1. Create integration tests for capability flows
2. Test upgrade paths
3. Test limit enforcement
4. Test capability display in various contexts

## Migration Path

For existing code that checks plan IDs:

**Step 1: Identify**
```bash
grep -r "planid ===" src/
grep -r "plan_id ===" src/
```

**Step 2: Replace**
```typescript
// Before
if (org.planid === 'identity_v1') { ... }

// After
if (can(CAPABILITIES.CUSTOM_DOMAINS)) { ... }
```

**Step 3: Add Upgrade Prompts**
```vue
<!-- Before -->
<div v-if="org.planid === 'identity_v1'">...</div>

<!-- After -->
<div v-if="can(CAPABILITIES.CUSTOM_DOMAINS)">...</div>
<UpgradePrompt v-else ... />
```

## Maintenance

### Adding New Capabilities
1. Add to `CAPABILITIES` constant in `src/types/organization.ts`
2. Add upgrade message to `src/locales/en.json`
3. Add to `upgradePath()` mapping in composable
4. Add to `formatCapability()` in display components

### Adding New Limits
1. Add to `OrganizationLimits` interface
2. Update Zod schema
3. Use `limit()` and `hasReachedLimit()` in components

## Support

See `docs/capability-based-ui-integration.md` for:
- Detailed usage examples
- Complete API documentation
- Anti-patterns to avoid
- Testing scenarios
- Troubleshooting guide
