<script setup lang="ts">
import HomepageTaglines from '@/components/HomepageTaglines.vue';
import InboundSecretForm from '@/components/secrets/form/InboundSecretForm.vue';
import { WindowService } from '@/services/window.service';

const authenticated = WindowService.get('authenticated') ?? false;

</script>

<template>
  <div class="rounded-lg bg-white p-6 shadow-md dark:bg-gray-800">
    <HomepageTaglines v-if="authenticated" />

    <InboundSecretForm
      :enabled="true"
      :title="$t('support-details')"
    />
  </div>
</template>
