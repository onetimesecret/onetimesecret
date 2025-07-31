<!-- src/components/layout/HeaderUserNav.vue -->

<script setup lang="ts">
  import FancyIconLink from '@/components/ctas/FancyIconLink.vue';
  import { Customer } from '@/schemas/models';
  import OIcon from '@/components/icons/OIcon.vue';
  import { ref, computed } from 'vue';
  import { WindowService } from '@/services/window.service';

  // Access the necessary window properties with defaults
  const windowProps = WindowService.getMultiple(['domains_enabled']);

  const domainsEnabled = windowProps.domains_enabled;
  const showUpgrade = computed(() => domainsEnabled);

  // Allows for highlighting feature to user just one
  // time to false after user has seen it once. Setting
  // to false disables altogether but defaulting to true
  // and flipping a localStorage flag to false after user
  // has seen it once is a good way to handle this.
  const isNewFeature = ref(false);

  defineProps<{
    cust: Customer;
    colonel?: boolean;
  }>();
</script>

<template>
  <div class="hidden items-center sm:flex">
    <router-link
      to="/account"
      class="group text-gray-400 transition hover:text-gray-300">
      <span
        id="userEmail"
        :class="{ 'animate-pulse': isNewFeature }"
        class="group-hover:text-gray-300">
        {{ cust.custid }}
      </span>
    </router-link>

    <FancyIconLink
      v-if="showUpgrade"
      to="/pricing"
      :aria-label="$t('click-this-lightning-bolt-to-upgrade-for-custom-domains')" />

    <router-link
      v-if="colonel"
      to="/colonel/"
      title=""
      class="ml-2 text-gray-400 transition hover:text-gray-300">
      <OIcon
        collection="mdi"
        name="star"
        class="size-4 text-brand-400" />
    </router-link>
    <span
      class="ml-2 text-gray-400"
      aria-hidden="true"
      role="separator"
      >|</span
    >
  </div>
</template>

<style>
  @keyframes pulse {
    0%,
    100% {
      opacity: 1;
    }

    50% {
      opacity: 0.5;
    }
  }

  .animate-pulse {
    animation: pulse 4s cubic-bezier(0.4, 0, 0.6, 1) infinite;
  }
</style>
