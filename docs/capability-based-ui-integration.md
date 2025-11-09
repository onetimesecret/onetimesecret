# Capability-Based UI Integration

This document demonstrates how to use capability-based access control in the Vue frontend to show/hide features based on organization capabilities.

## Key Principles

1. **Never check plan IDs in components** - Only check capabilities
2. **Fail safely** - Hide features if capability check fails
3. **Show upgrade prompts** - When capability missing, show clear upgrade path
4. **Cache capabilities** - Fetch once, reuse across components

## Implementation Overview

### 1. Organization Type with Capabilities

File: `/src/types/organization.ts`

```typescript
export const CAPABILITIES = {
  CREATE_SECRETS: 'create_secrets',
  BASIC_SHARING: 'basic_sharing',
  CREATE_TEAM: 'create_team',
  CREATE_TEAMS: 'create_teams',
  CUSTOM_DOMAINS: 'custom_domains',
  API_ACCESS: 'api_access',
  PRIORITY_SUPPORT: 'priority_support',
  AUDIT_LOGS: 'audit_logs',
} as const;

export interface Organization {
  // ... other fields
  planid?: string;
  capabilities?: Capability[];
  limits?: OrganizationLimits;
}
```

### 2. Capability Composable

File: `/src/composables/useCapabilities.ts`

```typescript
export function useCapabilities(org: Ref<Organization | null>) {
  const can = (capability: string): boolean => {
    if (!org.value) return false;
    return org.value.capabilities?.includes(capability) ?? false;
  };

  const limit = (resource: string): number => {
    if (!org.value) return 0;
    return org.value.limits?.[resource] ?? 0;
  };

  const upgradePath = (capability: string): string | null => {
    // Returns the plan ID needed for this capability
  };

  return { can, limit, upgradePath, capabilities, CAPABILITIES };
}
```

### 3. UpgradePrompt Component

File: `/src/components/billing/UpgradePrompt.vue`

A reusable component that displays an upgrade prompt when a capability is missing:

```vue
<UpgradePrompt
  :capability="CAPABILITIES.CREATE_TEAMS"
  :upgrade-plan="upgradePath(CAPABILITIES.CREATE_TEAMS) || 'multi_team_v1'"
  :message="t('web.billing.upgrade.needTeams')"
/>
```

Props:
- `capability`: The capability being checked
- `upgradePlan`: The plan ID to upgrade to
- `message`: Optional custom message (falls back to i18n)
- `compact`: Optional compact mode for inline display

### 4. Usage Examples

#### Example 1: Team Creation (TeamsHub.vue)

```vue
<script setup lang="ts">
import { useCapabilities } from '@/composables/useCapabilities';
import UpgradePrompt from '@/components/billing/UpgradePrompt.vue';

const { currentOrganization } = storeToRefs(organizationStore);
const { can, hasReachedLimit, limit, upgradePath, CAPABILITIES } = useCapabilities(
  currentOrganization
);

const canCreateTeam = computed(() => {
  return can(CAPABILITIES.CREATE_TEAM) || can(CAPABILITIES.CREATE_TEAMS);
});

const teamLimitReached = computed(() => {
  const teamLimit = limit('teams');
  if (teamLimit === 0) return false; // No limit
  return hasReachedLimit('teams', teams.value.length);
});
</script>

<template>
  <!-- Upgrade Prompt if capability missing -->
  <UpgradePrompt
    v-if="!canCreateTeam"
    :capability="CAPABILITIES.CREATE_TEAM"
    :upgrade-plan="upgradePath(CAPABILITIES.CREATE_TEAM) || 'multi_team_v1'"
    :message="t('web.billing.upgrade.needTeams')"
  />

  <!-- Upgrade Prompt if limit reached -->
  <UpgradePrompt
    v-else-if="teamLimitReached"
    :capability="CAPABILITIES.CREATE_TEAMS"
    :upgrade-plan="upgradePath(CAPABILITIES.CREATE_TEAMS) || 'multi_team_v1'"
    :message="t('web.billing.limits.teams_upgrade')"
  />

  <!-- Create button only shown if capable -->
  <button
    v-if="canCreateTeam && !teamLimitReached"
    @click="showCreateModal = true">
    Create Team
  </button>
</template>
```

#### Example 2: Custom Domains

```vue
<script setup lang="ts">
import { useCapabilities } from '@/composables/useCapabilities';
import UpgradePrompt from '@/components/billing/UpgradePrompt.vue';

const { currentOrganization } = storeToRefs(organizationStore);
const { can, upgradePath, CAPABILITIES } = useCapabilities(currentOrganization);
</script>

<template>
  <div v-if="can(CAPABILITIES.CUSTOM_DOMAINS)">
    <!-- Domain management UI -->
  </div>

  <UpgradePrompt
    v-else
    :capability="CAPABILITIES.CUSTOM_DOMAINS"
    :upgrade-plan="upgradePath(CAPABILITIES.CUSTOM_DOMAINS)"
    :message="t('web.billing.upgrade.needCustomDomains')"
  />
</template>
```

#### Example 3: API Settings

```vue
<script setup lang="ts">
import { useCapabilities } from '@/composables/useCapabilities';
import UpgradePrompt from '@/components/billing/UpgradePrompt.vue';

const { currentOrganization } = storeToRefs(organizationStore);
const { can, upgradePath, CAPABILITIES } = useCapabilities(currentOrganization);
</script>

<template>
  <div v-if="can(CAPABILITIES.API_ACCESS)">
    <!-- API key management -->
  </div>

  <UpgradePrompt
    v-else
    :capability="CAPABILITIES.API_ACCESS"
    :upgrade-plan="upgradePath(CAPABILITIES.API_ACCESS)"
    :message="t('web.billing.upgrade.needApiAccess')"
  />
</template>
```

#### Example 4: Display Current Capabilities (OrganizationSettings.vue)

```vue
<script setup lang="ts">
import { useCapabilities } from '@/composables/useCapabilities';
import { CAPABILITIES } from '@/types/organization';

const { capabilities } = useCapabilities(organization);

const formatCapability = (cap: string): string => {
  const labels: Record<string, string> = {
    [CAPABILITIES.CREATE_SECRETS]: 'Create Secrets',
    [CAPABILITIES.BASIC_SHARING]: 'Basic Sharing',
    [CAPABILITIES.CREATE_TEAM]: 'Create Team',
    [CAPABILITIES.CREATE_TEAMS]: 'Create Multiple Teams',
    [CAPABILITIES.CUSTOM_DOMAINS]: 'Custom Domains',
    [CAPABILITIES.API_ACCESS]: 'API Access',
    [CAPABILITIES.PRIORITY_SUPPORT]: 'Priority Support',
    [CAPABILITIES.AUDIT_LOGS]: 'Audit Logs',
  };
  return labels[cap] || cap;
};
</script>

<template>
  <div class="current-capabilities">
    <h5>Your Plan Includes:</h5>
    <div class="grid grid-cols-2 gap-2">
      <div v-for="cap in capabilities" :key="cap" class="flex items-center gap-2">
        <OIcon collection="heroicons" name="check-circle" class="size-5 text-green-500" />
        {{ formatCapability(cap) }}
      </div>
    </div>
  </div>
</template>
```

### 5. Organization Store Integration

File: `/src/stores/organizationStore.ts`

```typescript
async function fetchCapabilities(orgId: string): Promise<void> {
  try {
    const response = await $api.get(`/api/billing/capabilities/${orgId}`);

    // Update the organization with capabilities
    const index = organizations.value.findIndex((o) => o.id === orgId);
    if (index !== -1) {
      organizations.value[index] = {
        ...organizations.value[index],
        planid: response.data.planid,
        capabilities: response.data.capabilities,
        limits: response.data.limits,
      };
    }

    // Update current organization if it matches
    if (currentOrganization.value?.id === orgId) {
      currentOrganization.value = {
        ...currentOrganization.value,
        planid: response.data.planid,
        capabilities: response.data.capabilities,
        limits: response.data.limits,
      };
    }
  } catch (err) {
    console.error('[OrganizationStore] Error fetching capabilities:', err);
    // Don't throw - capabilities are optional enhancements
  }
}
```

### 6. i18n Keys

File: `/src/locales/en.json`

```json
{
  "web": {
    "billing": {
      "upgrade": {
        "required": "Upgrade Required",
        "viewPlans": "View Plans",
        "needTeams": "Multiple teams require Multi-Team plan or higher",
        "needCustomDomains": "Custom domains require Identity Plus or higher",
        "needApiAccess": "API access requires Multi-Team plan or higher",
        "needPrioritySupport": "Priority support requires Identity Plus or higher",
        "needAuditLogs": "Audit logs require Multi-Team plan or higher"
      },
      "limits": {
        "teams_reached": "You've reached your plan limit",
        "teams_upgrade": "Upgrade to create more teams"
      }
    }
  }
}
```

## Anti-Patterns to Avoid

### ❌ DON'T: Check plan IDs
```vue
<button v-if="org.planid === 'identity_v1'">
  Add Domain
</button>
```

### ✅ DO: Check capabilities
```vue
<button v-if="can(CAPABILITIES.CUSTOM_DOMAINS)">
  Add Domain
</button>
```

### ❌ DON'T: Hardcode plan names in UI
```vue
<p>Upgrade to Identity Plus to unlock this feature</p>
```

### ✅ DO: Display capabilities as features
```vue
<UpgradePrompt
  :capability="CAPABILITIES.CUSTOM_DOMAINS"
  :upgrade-plan="upgradePath(CAPABILITIES.CUSTOM_DOMAINS)"
/>
```

### ❌ DON'T: Check limits in components
```vue
<button v-if="teams.length < 5">Create Team</button>
```

### ✅ DO: Use the composable
```vue
<button v-if="!hasReachedLimit('teams', teams.length)">
  Create Team
</button>
```

## Backend API Contract

The backend should provide a `/api/billing/capabilities/:orgId` endpoint that returns:

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

Limits with value `0` or missing means unlimited/not available.

## Testing Scenarios

1. **No capabilities**: User should see upgrade prompts everywhere
2. **Basic capabilities**: User can create secrets but not teams
3. **Team capability**: User can create one team but not multiple
4. **Teams capability**: User can create multiple teams up to limit
5. **At limit**: User sees upgrade prompt when limit reached
6. **Full capabilities**: All features available

## Files Modified

- `/src/types/organization.ts` - Added capabilities and limits
- `/src/composables/useCapabilities.ts` - Created capability checking composable
- `/src/components/billing/UpgradePrompt.vue` - Created upgrade prompt component
- `/src/stores/organizationStore.ts` - Added fetchCapabilities method
- `/src/views/teams/TeamsHub.vue` - Integrated capability checks
- `/src/views/account/settings/OrganizationSettings.vue` - Display current capabilities
- `/src/locales/en.json` - Added upgrade message i18n keys
