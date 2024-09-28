<!-- eslint-disable vue/multi-word-component-names -->

<template>
  <div>
    <section class="mb-8">
      <h1 class="font-semibold mb-6 text-gray-900 dark:text-gray-100">Signup</h1>
      <h3 class=" font-semibold mb- text-gray-900 dark:text-gray-100">
        Our {{ currentPlan.options.name }} plan! You get:
      </h3>

      <ul class="list-disc pl-6 text-gray-700 dark:text-gray-300">
        <li>secrets that live up to <span class="font-bold text-brand-600 dark:text-brand-400">{{currentPlan.options.ttl/3600/24}} days</span>.</li>
        <li v-if="currentPlan.options.email">to send secret links via <span class="font-bold text-brand-600 dark:text-brand-400">email</span>.</li>
        <li v-if="currentPlan.options.api">access to the <a :href="`${supportHost}/docs/rest-api`" class="font-bold text-brand-600 dark:text-brand-400 hover:underline">API</a>.</li>
      </ul>
    </section>

    <PlansElevateCta />

    <SignUpForm :planid="currentPlanId" />

    <div class="mt-6 text-center">
      <router-link to="/signin" class="text-sm text-gray-600 dark:text-gray-400 hover:underline">
        Already have an account? <strong class="font-medium text-gray-900 dark:text-gray-200">Sign In</strong>
      </router-link>
    </div>
  </div>
</template>

<script setup lang="ts">
import PlansElevateCta from '@/components/ctas/PlansElevateCta.vue';
import SignUpForm from '@/components/auth/SignUpForm.vue';
import { useWindowProp } from '@/composables/useWindowProps';

// This prop is passed from vue-router b/c the route has `prop: true`.
interface Props {
  planCode: string
}

const props = defineProps<Props>()

const currentPlanId = props.planCode || 'basic';
const availablePlans = window.available_plans;
const currentPlan = availablePlans[currentPlanId];
const supportHost = useWindowProp('support_host');

</script>
