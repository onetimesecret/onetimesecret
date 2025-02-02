<script setup lang="ts">
import StarsRating from "@/components/StarsRating.vue";
import { Testimonial } from "@/sources/testimonials";

// Define props using defineProps
const props = defineProps<{
  testimonial: Testimonial;
}>();

</script>

<template>
  <div class="mx-auto max-w-2xl px-4 pb-12 pt-24 sm:px-6 lg:px-8">
    <h2 class="mb-8 text-left text-3xl font-bold text-gray-900 dark:text-white">
      <span class="text-xl font-semibold text-gray-700 dark:text-gray-300">{{ $t('ai-generated-testimonials') }}</span>
      <br />
      <span>{{ $t('what-leading-ai-says-about-us') }}:</span>
    </h2>

    <div class="overflow-hidden rounded-lg bg-white shadow-lg dark:bg-gray-800">
      <div class="p-6 sm:p-8">
        <svg
          class="mb-4 size-5 text-brand-500"
          fill="currentColor"
          viewBox="0 0 24 24"
          width="20"
          height="20">
          <path d="M14.017 21v-7.391c0-5.704 3.731-9.57 8.983-10.609l.995 2.151c-2.432.917-3.995 3.638-3.995 5.849h4v10h-9.983zm-14.017 0v-7.391c0-5.704 3.748-9.57 9-10.609l.996 2.151c-2.433.917-3.996 3.638-3.996 5.849h3.983v10h-9.983z" />
        </svg>

        <p class="mb-6 text-lg italic leading-relaxed text-gray-700 dark:text-gray-300">
          "{{ props.testimonial.quote }}"
        </p>

        <div class="flex items-center justify-between">
          <div>
            <p class="font-semibold text-gray-900 dark:text-white">
              {{ props.testimonial.name }}
            </p>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              {{ props.testimonial.company }}
            </p>
          </div>

          <div class="flex items-center">
            <StarsRating :stars="props.testimonial.stars" />
          </div>
        </div>
      </div>

      <div class="bg-gray-100 px-6 py-4 dark:bg-gray-700">
        <p class="text-sm italic text-gray-600 dark:text-gray-400">
          {{ $t('note') }}: <span class="">{{ $t('this-quote-was-generated-by') }} <a
            href="https://www.anthropic.com/news/claude-3-5-sonnet"
            class="underline"
            rel="noopener noreferrer"
            target="_blank">Claude 3.5</a></span>. {{ $t('it-was-based-on-the-content-of-the-page-and-does') }}
        </p>
      </div>
    </div>
  </div>
</template>
