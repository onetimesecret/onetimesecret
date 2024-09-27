<script setup lang="ts">
/**
 * This separate <script> block is necessary to define props that depend on module-scope variables.
 * Vue 3's <script setup> compilation hoists defineProps() outside the setup() function,
 * which prevents it from accessing locally declared variables.
 * By using a normal <script> block, we can safely initialize our props with module-scope values.
 */
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import { useWindowProps } from '@/composables/useWindowProps';
import SecretMetadataTable from '@/components/secrets/SecretMetadataTable.vue';

const { notreceived, received, has_items } = useWindowProps(['notreceived', 'received', 'has_items']);

// You can use props here if needed
 console.log(has_items.value);
</script>

<template>
  <div>
    <DashboardTabNav />

    <SecretMetadataTable :hasItems="has_items"
                        :notReceived="notreceived"
                        :received="received"
                        title="Received" />
  </div>
</template>
