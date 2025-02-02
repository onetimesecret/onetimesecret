<script setup lang="ts">
import { testimonials } from '@/sources/testimonials'; // Adjust the path as necessary
import { ref, computed } from 'vue';

const currentIndex = ref(0);

const nextTestimonial = () => {
  currentIndex.value = (currentIndex.value + 1) % testimonials.length;
};

const previousTestimonial = () => {
  currentIndex.value = (currentIndex.value - 1 + testimonials.length) % testimonials.length;
};

const currentTestimonial = computed(() => testimonials[currentIndex.value]);
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 py-12 sm:px-6 lg:px-8">
    <div class="overflow-hidden rounded-lg bg-white shadow-md dark:bg-gray-800">
      <div class="p-6 sm:p-8">
        <div class="mb-4 hidden items-center ">
          <svg
            class="mr-2 size-6 text-brand-500"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            xmlns="http://www.w3.org/2000/svg"
            width="24"
            height="24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z"
            />
          </svg>
          <span class="text-sm font-medium text-gray-500 dark:text-gray-400">{{ $t('artificial-feedback') }}</span>
        </div>
        <blockquote class="mb-4 text-lg font-medium italic text-gray-900 dark:text-white sm:text-xl">
          "{{ currentTestimonial.quote }}"
        </blockquote>
        <div class="flex items-center">
          <div class="shrink-0">
            <svg
              class="size-8 text-gray-400"
              fill="currentColor"
              viewBox="0 0 20 20"
              xmlns="http://www.w3.org/2000/svg"
              width="32"
              height="32">
              <path
                fill-rule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-6-3a2 2 0 11-4 0 2 2 0 014 0zm-2 4a5 5 0 00-4.546 2.916A5.986 5.986 0 0010 16a5.986 5.986 0 004.546-2.084A5 5 0 0010 11z"
                clip-rule="evenodd"
              />
            </svg>
          </div>
          <div class="ml-3">
            <p class="text-sm font-medium text-gray-900 dark:text-white">
              {{ currentTestimonial.name }}
            </p>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              {{ currentTestimonial.company }}
            </p>
          </div>
        </div>
      </div>
      <div class="bg-gray-100 px-6 py-3 dark:bg-gray-700">
        <p class="text-xs text-gray-500 dark:text-gray-400">
          {{ $t('note') }}: {{ $t('this-content-is-ai-generated-based-on-the-conten') }}
        </p>
      </div>
      <div class="flex justify-between px-6 py-3">
        <button
          @click="previousTestimonial"
          class="text-sm font-medium text-gray-500 dark:text-gray-400">
          {{ $t('previous') }}
        </button>
        <button
          @click="nextTestimonial"
          class="text-sm font-medium text-gray-500 dark:text-gray-400">
          {{ $t('next') }}
        </button>
      </div>
    </div>
  </div>
</template>
