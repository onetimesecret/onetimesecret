<!--
  On importing components: change the import statement to import GlobalBroadcast as a default import, not a named import.

  `import { GlobalBroadcast } from '~/components/GlobalBroadcast.vue';` -- Incorrect ❌
  `import GlobalBroadcast from '~/components/GlobalBroadcast.vue';` -- Correct ✅

-->
<template>

  <div v-if="show"
       class="relative isolate flex items-center gap-x-6 overflow-hidden bg-gray-50  dark:bg-gray-900 px-6 py-2.5 sm:px-3.5 sm:before:flex-1">
    <div class="absolute left-[max(-7rem,calc(50%-52rem))] top-1/2 -z-10 -translate-y-1/2 transform-gpu blur-2xl"
         aria-hidden="true">
      <div class="aspect-[577/310] w-[36.0625rem] bg-gradient-to-r from-[#dc4a22] to-[#fcf4e8] opacity-30"
           style="clip-path: polygon(74.8% 41.9%, 97.2% 73.2%, 100% 34.9%, 92.5% 0.4%, 87.5% 0%, 75% 28.6%, 58.5% 54.6%, 50.1% 56.8%, 46.9% 44%, 48.3% 17.4%, 24.7% 53.9%, 0% 27.9%, 11.9% 74.2%, 24.9% 54.1%, 68.6% 100%, 74.8% 41.9%)" />
    </div>
    <div class="absolute left-[max(45rem,calc(50%+8rem))] top-1/2 -z-10 -translate-y-1/2 transform-gpu blur-2xl"
         aria-hidden="true">
      <div class="aspect-[577/310] w-[36.0625rem] bg-gradient-to-r from-[#dc4a22] to-[#fcf4e8] opacity-30"
           style="clip-path: polygon(74.8% 41.9%, 97.2% 73.2%, 100% 34.9%, 92.5% 0.4%, 87.5% 0%, 75% 28.6%, 58.5% 54.6%, 50.1% 56.8%, 46.9% 44%, 48.3% 17.4%, 24.7% 53.9%, 0% 27.9%, 11.9% 74.2%, 24.9% 54.1%, 68.6% 100%, 74.8% 41.9%)" />
    </div>
    <p class="text-sm leading-6 text-gray-900 dark:text-gray-100">
      <a href="#">
        <strong class="font-semibold"></strong><svg viewBox="0 0 2 2"
             class="mx-2 inline h-0.5 w-0.5 fill-current"
             aria-hidden="true">
          <circle cx="1"
                  cy="1"
                  r="1" />
        </svg>

        {{ content }}

        <!--&nbsp;<span aria-hidden="true">&rarr;</span>-->
      </a>
    </p>
    <div class="flex flex-1 justify-end">
      <button type="button"
              class="-m-3 p-3 focus-visible:outline-offset-[-4px]">
        <span class="sr-only">Dismiss</span>

        <Icon icon="heroicons-solid:xmarkicon"
              class="h-5 w-5 text-gray-900 dark:text-gray-100"
              aria-hidden="true" />
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
// https://iconify.design/docs/icon-components/vue/
import { Icon } from '@iconify/vue';
import { defineProps, withDefaults } from 'vue';


// TypeScript with Composition API
//
// Note that default values for mutable reference types (like arrays or
// objects) should be wrapped in functions to avoid accidental
// modification and external side effects. This ensures each component
// instance gets its own copy of the default value.
//
// See: https://vuejs.org/guide/typescript/composition-api.html#props-default-values


export interface Props {
  content: string;
  show: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  content: "Welcome to the Global Broadcast!",
  show: false,
})

console.log(props);
</script>
