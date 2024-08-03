
<!--
  EXAMPLE USAGE:

  <template>
    <div>
      <QuoteBlock :testimonial="testimonial" />
    </div>
  </template>

  <script setup lang="ts">
  import { ref } from 'vue';
  import QuoteBlock from './QuoteBlock.vue';

  const testimonial = ref({
    quote: "This is an amazing product! It has changed the way we work.",
    name: "John Doe",
    company: "Tech Corp"
  });
  </script>

-->
<template>
  <div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
    <div class="bg-white dark:bg-gray-800 rounded-lg shadow-md overflow-hidden">
      <div class="p-6 sm:p-8">
        <div class="hidden items-center mb-4 ">
          <svg class="w-6 h-6 text-brand-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" width="24" height="24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z"></path>
          </svg>
          <span class="text-sm font-medium text-gray-500 dark:text-gray-400">Artificial Feedback</span>
        </div>
        <blockquote class="text-lg sm:text-xl font-medium text-gray-900 dark:text-white mb-4 italic">
          "{{ props.testimonial.quote }}"
        </blockquote>
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <svg class="w-8 h-8 text-gray-400" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg" width="32" height="32">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-6-3a2 2 0 11-4 0 2 2 0 014 0zm-2 4a5 5 0 00-4.546 2.916A5.986 5.986 0 0010 16a5.986 5.986 0 004.546-2.084A5 5 0 0010 11z" clip-rule="evenodd"></path>
            </svg>
          </div>
          <div class="ml-3">
            <p class="text-sm font-medium text-gray-900 dark:text-white">
              {{ props.testimonial.name }}
            </p>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              {{ props.testimonial.company }}
            </p>
          </div>
        </div>
      </div>
      <div class="bg-gray-100 dark:bg-gray-700 px-6 py-3">
        <p class="text-xs text-gray-500 dark:text-gray-400">
          Note: This quote is AI-generated based on the content of this page and does not represent an actual person or company.
        </p>
      </div>
    </div>
  </div>

</template>

<script setup lang="ts">

interface Testimonial {
  quote: string;
  name: string;
  company: string;
}

// Define props using defineProps
const props = defineProps<{
  testimonial: Testimonial;
}>();

</script>
