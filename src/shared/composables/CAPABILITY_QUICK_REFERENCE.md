# Capability-Based UI - Quick Reference

## Import and Setup

```typescript
import { useCapabilities } from '@/composables/useCapabilities';
import { CAPABILITIES } from '@/types/organization';
import UpgradePrompt from '@/components/billing/UpgradePrompt.vue';
import { useOrganizationStore } from '@/stores/organizationStore';

const organizationStore = useOrganizationStore();
const { currentOrganization } = storeToRefs(organizationStore);
const { can, limit, upgradePath, hasReachedLimit, CAPABILITIES } = useCapabilities(
  currentOrganization
);
```

## Check if Feature is Available

```typescript
// Single capability
const canUseDomains = can(CAPABILITIES.CUSTOM_DOMAINS);

// Multiple capabilities (OR)
const canCreateTeam = can(CAPABILITIES.CREATE_TEAM) || can(CAPABILITIES.CREATE_TEAMS);

// With limit check
const teamLimit = limit('teams');
const teamsLimitReached = hasReachedLimit('teams', currentTeamCount);
const canAddTeam = canCreateTeam && !teamsLimitReached;
```

## Show/Hide UI Elements

```vue
<template>
  <!-- Simple show/hide -->
  <button v-if="can(CAPABILITIES.API_ACCESS)">
    Manage API Keys
  </button>

  <!-- Show upgrade prompt if not available -->
  <div v-if="can(CAPABILITIES.CUSTOM_DOMAINS)">
    <!-- Feature UI -->
  </div>
  <UpgradePrompt
    v-else
    :capability="CAPABILITIES.CUSTOM_DOMAINS"
    :upgrade-plan="upgradePath(CAPABILITIES.CUSTOM_DOMAINS)"
  />
</template>
```

## With Limit Checking

```vue
<template>
  <!-- Check both capability and limit -->
  <div class="space-y-4">
    <UpgradePrompt
      v-if="!can(CAPABILITIES.CREATE_TEAMS)"
      :capability="CAPABILITIES.CREATE_TEAMS"
      :upgrade-plan="upgradePath(CAPABILITIES.CREATE_TEAMS)"
    />

    <UpgradePrompt
      v-else-if="hasReachedLimit('teams', teams.length)"
      :capability="CAPABILITIES.CREATE_TEAMS"
      :upgrade-plan="upgradePath(CAPABILITIES.CREATE_TEAMS)"
      :message="t('web.billing.limits.teams_upgrade')"
    />

    <button
      v-else
      @click="createTeam">
      Create Team
    </button>
  </div>
</template>
```

## Available Capabilities

```typescript
CAPABILITIES.CREATE_SECRETS      // Can create secrets
CAPABILITIES.BASIC_SHARING       // Can share secrets
CAPABILITIES.CREATE_TEAM         // Can create one team
CAPABILITIES.CREATE_TEAMS        // Can create multiple teams
CAPABILITIES.CUSTOM_DOMAINS      // Can use custom domains
CAPABILITIES.API_ACCESS          // Can use API
CAPABILITIES.PRIORITY_SUPPORT    // Has priority support
CAPABILITIES.AUDIT_LOGS          // Has access to audit logs
```

## Available Limits

```typescript
limit('teams')              // Max number of teams
limit('members_per_team')   // Max members per team
limit('custom_domains')     // Max custom domains
```

## Upgrade Prompt Props

```vue
<UpgradePrompt
  capability="create_teams"          // Required: capability being checked
  upgrade-plan="multi_team_v1"       // Required: plan to upgrade to
  :message="customMessage"           // Optional: custom message
  :compact="true"                    // Optional: compact display mode
/>
```

## Get Upgrade Plan for Capability

```typescript
const planNeeded = upgradePath(CAPABILITIES.API_ACCESS);
// Returns: "multi_team_v1" or null if already available
```

## Display Current Capabilities

```typescript
import { computed } from 'vue';

const { capabilities } = useCapabilities(currentOrganization);

const formatCapability = (cap: string): string => {
  const labels: Record<string, string> = {
    [CAPABILITIES.CREATE_SECRETS]: 'Create Secrets',
    [CAPABILITIES.CUSTOM_DOMAINS]: 'Custom Domains',
    // ... etc
  };
  return labels[cap] || cap;
};
```

```vue
<template>
  <div v-for="cap in capabilities" :key="cap">
    <OIcon name="check-circle" class="text-green-500" />
    {{ formatCapability(cap) }}
  </div>
</template>
```

## Common Patterns

### Pattern 1: Feature with Fallback
```vue
<div v-if="can(CAPABILITIES.FEATURE)">
  <!-- Full feature UI -->
</div>
<div v-else>
  <UpgradePrompt ... />
</div>
```

### Pattern 2: Conditional Button
```vue
<button
  v-if="can(CAPABILITIES.FEATURE) && !limitReached"
  @click="action">
  Action
</button>
```

### Pattern 3: Tab/Section Visibility
```vue
<nav>
  <button
    v-if="can(CAPABILITIES.API_ACCESS)"
    @click="activeTab = 'api'">
    API Settings
  </button>
</nav>
```

### Pattern 4: Empty State with Upgrade
```vue
<div v-if="items.length === 0">
  <div v-if="can(CAPABILITIES.FEATURE)">
    <p>No items yet</p>
    <button @click="create">Create First Item</button>
  </div>
  <UpgradePrompt v-else ... />
</div>
```

## Don't Do This

```typescript
// ❌ Don't check plan IDs
if (org.planid === 'identity_v1') { }

// ❌ Don't hardcode plan names
<p>Upgrade to Identity Plus</p>

// ❌ Don't check limits without capability
if (teams.length < 5) { }
```

## Do This Instead

```typescript
// ✅ Check capabilities
if (can(CAPABILITIES.CUSTOM_DOMAINS)) { }

// ✅ Use upgrade path helper
<UpgradePrompt :upgrade-plan="upgradePath(cap)" />

// ✅ Check both capability and limit
if (can(CAPABILITIES.CREATE_TEAMS) && !hasReachedLimit('teams', count)) { }
```

## Testing Scenarios

1. **No organization** - All checks return false
2. **No capabilities** - Show upgrade prompts everywhere
3. **Basic capabilities** - Some features available
4. **At limit** - Show limit reached prompts
5. **Full access** - All features available

## Troubleshooting

**Features not showing up?**
- Check that `currentOrganization` is set
- Check that `fetchCapabilities()` has been called
- Check console for capability fetch errors

**Wrong upgrade plan showing?**
- Update `upgradePath()` mapping in composable
- Check backend capability-to-plan mapping

**Limits not working?**
- Verify limit values in backend response
- Check that limit name matches (`teams`, not `team`)
- Ensure `hasReachedLimit()` uses correct resource name
