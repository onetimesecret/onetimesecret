
<template>
  <div :class="['mx-auto aspect-[1155/678] w-[72.1875rem] opacity-30']"
       :style="{
           clipPath: clipPath,
         transition: `clip-path ${props.speed} ease`,
         background: `linear-gradient(to top right, ${props.fromColour}, ${props.toColour})`
       }" />
  </template>

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
  // Example: Update clip-path every 2 seconds
  setInterval(updateClipPath, props.interval);
});

export interface Props {
  fromColour: string;
  toColour: string;
  interval: number;
  speed: string;
}

const props = withDefaults(defineProps<Props>(), {
  fromColour: '#655b5f',
  toColour: '#23b5dd',
  interval: 2000,
  speed: '6s',
})

</script>
