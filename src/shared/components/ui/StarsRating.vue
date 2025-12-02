<!-- src/components/StarsRating.vue -->

<script setup lang="ts">

interface Props {
  stars: number;
}

const props = withDefaults(defineProps<Props>(), {
  stars: 2.5
});

const fullStars = Math.floor(props.stars);
const hasHalfStar = props.stars % 1 !== 0;
const emptyStars = 5 - Math.ceil(props.stars);
</script>

<template>
  <div class="flex items-center">
    <!-- Full Stars -->
    <svg
      v-for="i in fullStars"
      :key="'full-' + i"
      class="size-5 text-yellow-400"
      fill="currentColor"
      viewBox="0 0 20 20"
      width="20"
      height="20">
      <path
        d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
    </svg>
    <!-- Half Star -->
    <svg
      v-if="hasHalfStar"
      class="size-5 text-yellow-400"
      fill="currentColor"
      viewBox="0 0 20 20"
      width="20"
      height="20">
      <defs>
        <!-- Linear Gradient: A linear gradient is defined with an ID of half.
             It transitions from the current color to white at the halfway point. -->
        <linearGradient id="half">
          <stop
            offset="50%"
            stop-color="currentColor" />
          <stop
            offset="50%"
            stop-color="white"
            stop-opacity="1" />
        </linearGradient>
      </defs>
      <!-- Path Fill: The path is filled with the linear gradient,
           which effectively renders only half of the star. -->
      <path
        fill="url(#half)"
        d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
    </svg>
    <!-- Empty Stars -->
    <svg
      v-for="i in emptyStars"
      :key="'empty-' + i"
      class="size-5 text-gray-300"
      fill="currentColor"
      viewBox="0 0 20 20"
      width="20"
      height="20">
      <path
        d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
    </svg>
  </div>
</template>
