<script setup lang="ts">
import PlansElevateCta from '@/components/ctas/PlansElevateCta.vue';
import SignUpForm from '@/components/auth/SignUpForm.vue';

const currentPlanId = 'basic';
const availablePlans = window.available_plans ?? {};
const default_plan = availablePlans[currentPlanId];

const shrimp = window.shrimp ?? null;

</script>

<template>
  <div>
    <section class="mb-8">
      <h1 class="font-semibold mb-6 text-gray-900 dark:text-gray-100">Signup</h1>
      <h3 class=" font-semibold mb- text-gray-900 dark:text-gray-100">Our basic plan is free! You get:</h3>
      <ul class="list-disc pl-6 text-gray-700 dark:text-gray-300">
        <li>secrets that live up to <span class="font-bold text-brand-600 dark:text-brand-400">{{default_plan.options.ttl/3600/24}} days</span>.</li>
        <li v-if="default_plan.options.email">to send secret links via <span class="font-bold text-brand-600 dark:text-brand-400">email</span>.</li>
        <li v-if="default_plan.options.api">access to the <a href="/docs/api" class="font-bold text-brand-600 dark:text-brand-400 hover:underline">API</a>.</li>
      </ul>
    </section>

    <!--{{^hide_cta}}-->
      <PlansElevateCta />
    <!--{{/hide_cta}}-->

    <SignUpForm :shrimp="shrimp" :planid="currentPlanId" />

    <div class="mt-6 text-center">
      <a href="/signin" class="text-sm text-gray-600 dark:text-gray-400 hover:underline">
        Already have an account? <strong class="font-medium text-gray-900 dark:text-gray-200">Sign In</strong>
      </a>
    </div>
  </div>
</template>
