<!-- src/shared/components/ui/MovingGlobules.vue -->

<!--
  The shapes "jump" visually after the first interval because the initial
  [`clipPath`] value is set directly in the [`ref`]() without any transition. When
  the first update occurs, the transition is applied, but the initial change
  happens instantly, causing a visual "jump." Subsequent updates will have smooth
  transitions because the transition property is already in effect.

  To ensure smooth transitions from the start, you can set the initial
  [`clipPath`]() value with a transition. Here's how you can modify the code:
  1. Set the initial [`clipPath`]() value in a way that it transitions smoothly.
  2. Ensure the transition property is applied from the beginning.
-->

<script setup lang="ts">
import { ref, onMounted } from 'vue';

// Define clipPath as a reactive reference
const clipPath = ref('polygon(74.1% 44.1%, 100% 61.6%, 97.5% 26.9%, 85.5% 0.1%, 80.7% 2%, 72.5% 32.5%, 60.2% 62.4%, 52.4% 68.1%, 47.5% 58.3%, 45.2% 34.5%, 27.5% 76.7%, 0.1% 64.9%, 17.9% 100%, 27.6% 76.8%, 76.1% 97.7%, 74.1% 44.1%)');

// Method to update clipPath
function updateClipPath() {
  const points = [];
  for (let i = 0; i < 10; i++) {
    const x = Math.random() * 100;
    const y = Math.random() * 100;
    points.push(`${x.toFixed(1)}% ${y.toFixed(1)}%`);
  }
  clipPath.value = `polygon(${points.join(', ')})`;
}

onMounted(() => {
  // Set initial clipPath with a delay to ensure transition is applied
  setTimeout(() => {
    updateClipPath();
    // Update clip-path at regular intervals
    setInterval(updateClipPath, props.interval);
  }, 0);
});

export interface Props {
  fromColour: string;
  toColour: string;
  speed: string;
  interval?: number;
  scale: number;
}

const props = withDefaults(defineProps<Props>(), {
  fromColour: '#655b5f',
  toColour: '#23b5dd',
  speed: '6s',
  interval: 2000,
  scale: 1,
});

</script>

<template>
  <div
    class="absolute inset-x-0 -top-3 -z-10 transform-gpu overflow-hidden px-36 blur-3xl"
    aria-hidden="true">
    <div
      :class="['mx-auto aspect-[1155/678] w-[72.1875rem] opacity-30']"
      :style="{
        clipPath: clipPath,
        transition: `clip-path ${props.speed} ease`,
        background: `linear-gradient(to top right, ${props.fromColour}, ${props.toColour})`,
        transform: `scale(${props.scale})`
      }"></div>
  </div>
</template>
