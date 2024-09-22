<script setup lang="ts">
/**
 * This separate <script> block is necessary to define props that depend on module-scope variables.
 * Vue 3's <script setup> compilation hoists defineProps() outside the setup() function,
 * which prevents it from accessing locally declared variables.
 * By using a normal <script> block, we can safely initialize our props with module-scope values.
 */
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import { Metadata } from '@/types/onetime';

//const { notreceived, received, has_secrets, has_received, has_notreceived } = useWindowProps(['notreceived', 'received', 'has_secrets', 'has_received', 'has_notreceived']);

interface Props {
  hasSecrets?: boolean;
  hasNotReceived?: boolean;
  hasReceived?: boolean;
  notReceived?: Metadata[];
  received?: Metadata[];
}

defineProps<Props>();


// You can use props here if needed
// console.log(props.hasSecrets);
</script>

<template>
  <DashboardTabNav />

  <!-- Move to a separate component -->
  <div class="space-y-8">
    <template v-if="hasSecrets">
      <section>
        <h3 class="text-2xl font-semibold mb-4 text-gray-800 dark:text-gray-200">
            {{ $t('web.dashboard.title_not_received') }}
        </h3>
        <ul v-if="hasNotReceived" class="space-y-1">
          <li v-for="item in notReceived" :key="item.id">
            <!-- Assuming there's a component for li_metadata -->
            <LiMetadata :item="item" />
          </li>
        </ul>
        <p v-else class="text-gray-600 dark:text-gray-400 italic">
          Go on then.
            <a href="/" class="text-brand-500 hover:underline">{{ $t('web.COMMON.share_a_secret') }}!</a>
        </p>
      </section>

      <section>
        <h3 class="text-2xl font-semibold mb-4 text-gray-800 dark:text-gray-200">
            {{ $t('web.dashboard.title_received') }}
        </h3>
          <ul v-if="hasReceived" class="space-y-1">
            <li v-for="item in received" :key="item.id">
              <!-- Assuming there's a component for li_metadata -->
              <LiMetadata :item="item" />
            </li>
        </ul>
          <p v-else class="text-gray-600 dark:text-gray-400 italic">{{ $t('web.COMMON.word_none') }}</p>
      </section>
    </template>

    <template v-if="!hasSecrets">
      <section>
        <h3 class="text-2xl font-semibold mb-4 text-gray-800 dark:text-gray-200">
          {{ $t('web.dashboard.title_no_recent_secrets') }}
        </h3>
        <p class="text-gray-600 dark:text-gray-400 italic">
          Go on then.
          <a href="/" class="text-brand-500 hover:underline">{{ $t('web.COMMON.share_a_secret') }}!</a>
        </p>
      </section>
    </template>
  </div>
</template>
