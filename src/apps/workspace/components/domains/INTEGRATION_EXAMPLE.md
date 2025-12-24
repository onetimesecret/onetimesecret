# Privacy Defaults Components - Integration Example

This document shows how to integrate the Privacy Defaults components (`PrivacyDefaultsBar` and `PrivacyDefaultsModal`) into your views.

## Component Overview

### PrivacyDefaultsBar
A compact display bar showing the current domain's privacy defaults with an edit button.

### PrivacyDefaultsModal
A modal dialog for editing domain-specific privacy defaults (TTL, passphrase requirement, notifications).

## Integration Example

Here's how to add the Privacy Defaults Bar to the Dashboard (above the SecretForm):

```vue
<!-- src/apps/workspace/dashboard/DashboardIndex.vue -->

<script setup lang="ts">
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import PrivacyDefaultsBar from '@/apps/workspace/components/domains/PrivacyDefaultsBar.vue';
  import { useDomainScope } from '@/shared/composables/useDomainScope';
  import { useBranding } from '@/shared/composables/useBranding';
  import { WindowService } from '@/services/window.service';
  import { computed, onMounted } from 'vue';

  const cust = WindowService.get('cust');
  const isBetaEnabled = computed(() => cust?.feature_flags?.beta ?? false);

  // Domain scope management
  const { currentScope, isScopeActive } = useDomainScope();

  // Get brand settings for current domain
  const {
    brandSettings,
    isLoading,
    initialize: initBranding,
    saveBranding
  } = useBranding(currentScope.value.domain);

  // Initialize branding on mount
  onMounted(() => {
    if (isScopeActive.value) {
      initBranding();
    }
  });

  // Handle privacy defaults update
  const handlePrivacyUpdate = async (settings: Partial<BrandSettings>) => {
    await saveBranding(settings);
  };
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <!-- Privacy Defaults Bar (only shown when domain scope is active) -->
    <PrivacyDefaultsBar
      v-if="isScopeActive"
      :brand-settings="brandSettings"
      :is-loading="isLoading"
      @update="handlePrivacyUpdate"
      class="mb-4" />

    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true" />

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
```

## Standalone Usage

You can also use `PrivacyDefaultsModal` directly without the bar:

```vue
<script setup lang="ts">
  import { ref } from 'vue';
  import PrivacyDefaultsModal from '@/apps/workspace/components/domains/PrivacyDefaultsModal.vue';
  import type { BrandSettings } from '@/schemas/models';

  const isModalOpen = ref(false);
  const brandSettings = ref<BrandSettings>({
    default_ttl: 604800, // 7 days
    passphrase_required: false,
    notify_enabled: false,
  });

  const handleSave = async (settings: Partial<BrandSettings>) => {
    // Update via API
    await domainsStore.updateBrandSettings(domainExtid, settings);
    isModalOpen.value = false;
  };
</script>

<template>
  <button @click="isModalOpen = true">
    Edit Privacy Defaults
  </button>

  <PrivacyDefaultsModal
    :is-open="isModalOpen"
    :brand-settings="brandSettings"
    @close="isModalOpen = false"
    @save="handleSave" />
</template>
```

## API Integration

The components integrate with the existing `DomainsStore`:

```typescript
import { useDomainsStore } from '@/shared/stores/domainsStore';

const domainsStore = useDomainsStore();

// Update privacy defaults
await domainsStore.updateBrandSettings(domainExtid, {
  default_ttl: 3600,
  passphrase_required: true,
  notify_enabled: false,
});
```

## Backend Endpoint

The components use the existing brand settings API:

- **PUT** `/api/domains/:extid/brand`
  - Request body: `{ brand: { default_ttl, passphrase_required, notify_enabled } }`
  - Handled by: `apps/api/domains/logic/domains/update_domain_brand.rb`
