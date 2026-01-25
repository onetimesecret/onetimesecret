# Entitlement-Based UI - Quick Reference

## Import and Setup

```typescript
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { ENTITLEMENTS } from '@/types/organization';
import UpgradePrompt from '@/shared/components/billing/UpgradePrompt.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';

const organizationStore = useOrganizationStore();
const { currentOrganization } = storeToRefs(organizationStore);
const { can, limit, upgradePath, hasReachedLimit, ENTITLEMENTS } = useEntitlements(
  currentOrganization
);
```

## Check if Feature is Available

```typescript
// Single entitlement
const canUseDomains = can(ENTITLEMENTS.CUSTOM_DOMAINS);

// Multiple entitlements (OR)
const canCreateTeam = can(ENTITLEMENTS.CREATE_TEAM) || can(ENTITLEMENTS.CREATE_TEAMS);

// With limit check
const teamLimit = limit('teams');
const teamsLimitReached = hasReachedLimit('teams', currentTeamCount);
const canAddTeam = canCreateTeam && !teamsLimitReached;
```

## Show/Hide UI Elements

```vue
<template>
  <!-- Simple show/hide -->
  <button v-if="can(ENTITLEMENTS.API_ACCESS)">
    Manage API Keys
  </button>

  <!-- Show upgrade prompt if not available -->
  <div v-if="can(ENTITLEMENTS.CUSTOM_DOMAINS)">
    <!-- Feature UI -->
  </div>
  <UpgradePrompt
    v-else
    :entitlement="ENTITLEMENTS.CUSTOM_DOMAINS"
    :upgrade-plan="upgradePath(ENTITLEMENTS.CUSTOM_DOMAINS)"
  />
</template>
```

## With Limit Checking

```vue
<template>
  <!-- Check both entitlement and limit -->
  <div class="space-y-4">
    <UpgradePrompt
      v-if="!can(ENTITLEMENTS.CREATE_TEAMS)"
      :entitlement="ENTITLEMENTS.CREATE_TEAMS"
      :upgrade-plan="upgradePath(ENTITLEMENTS.CREATE_TEAMS)"
    />

    <UpgradePrompt
      v-else-if="hasReachedLimit('teams', teams.length)"
      :entitlement="ENTITLEMENTS.CREATE_TEAMS"
      :upgrade-plan="upgradePath(ENTITLEMENTS.CREATE_TEAMS)"
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

## Available Entitlements

```typescript
ENTITLEMENTS.CREATE_SECRETS      // Can create secrets
ENTITLEMENTS.BASIC_SHARING       // Can share secrets
ENTITLEMENTS.CREATE_TEAM         // Can create one team
ENTITLEMENTS.CREATE_TEAMS        // Can create multiple teams
ENTITLEMENTS.CUSTOM_DOMAINS      // Can use custom domains
ENTITLEMENTS.API_ACCESS          // Can use API
ENTITLEMENTS.PRIORITY_SUPPORT    // Has priority support
ENTITLEMENTS.AUDIT_LOGS          // Has access to audit logs
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
  entitlement="create_teams"          // Required: entitlement being checked
  upgrade-plan="multi_team_v1"        // Required: plan to upgrade to
  :message="customMessage"            // Optional: custom message
  :compact="true"                     // Optional: compact display mode
/>
```

## Get Upgrade Plan for Entitlement

```typescript
const planNeeded = upgradePath(ENTITLEMENTS.API_ACCESS);
// Returns: "multi_team_v1" or null if already available
```

## Display Current Entitlements

```typescript
import { computed } from 'vue';

const { entitlements } = useEntitlements(currentOrganization);

const formatEntitlement = (ent: string): string => {
  const labels: Record<string, string> = {
    [ENTITLEMENTS.CREATE_SECRETS]: 'Create Secrets',
    [ENTITLEMENTS.CUSTOM_DOMAINS]: 'Custom Domains',
    // ... etc
  };
  return labels[ent] || ent;
};
```

```vue
<template>
  <div v-for="ent in entitlements" :key="ent">
    <OIcon name="check-circle" class="text-green-500" />
    {{ formatEntitlement(ent) }}
  </div>
</template>
```

## Common Patterns

### Pattern 1: Feature with Fallback
```vue
<div v-if="can(ENTITLEMENTS.FEATURE)">
  <!-- Full feature UI -->
</div>
<div v-else>
  <UpgradePrompt ... />
</div>
```

### Pattern 2: Conditional Button
```vue
<button
  v-if="can(ENTITLEMENTS.FEATURE) && !limitReached"
  @click="action">
  Action
</button>
```

### Pattern 3: Tab/Section Visibility
```vue
<nav>
  <button
    v-if="can(ENTITLEMENTS.API_ACCESS)"
    @click="activeTab = 'api'">
    API Settings
  </button>
</nav>
```

### Pattern 4: Empty State with Upgrade
```vue
<div v-if="items.length === 0">
  <div v-if="can(ENTITLEMENTS.FEATURE)">
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

// ❌ Don't check limits without entitlement
if (teams.length < 5) { }
```

## Do This Instead

```typescript
// ✅ Check entitlements
if (can(ENTITLEMENTS.CUSTOM_DOMAINS)) { }

// ✅ Use upgrade path helper
<UpgradePrompt :upgrade-plan="upgradePath(ent)" />

// ✅ Check both entitlement and limit
if (can(ENTITLEMENTS.CREATE_TEAMS) && !hasReachedLimit('teams', count)) { }
```

## Testing Scenarios

1. **No organization** - All checks return false
2. **No entitlements** - Show upgrade prompts everywhere
3. **Basic entitlements** - Some features available
4. **At limit** - Show limit reached prompts
5. **Full access** - All features available

## Troubleshooting

**Features not showing up?**
- Check that `currentOrganization` is set
- Check that `fetchEntitlements()` has been called
- Check console for entitlement fetch errors

**Wrong upgrade plan showing?**
- Update `upgradePath()` mapping in composable
- Check backend entitlement-to-plan mapping

**Limits not working?**
- Verify limit values in backend response
- Check that limit name matches (`teams`, not `team`)
- Ensure `hasReachedLimit()` uses correct resource name
