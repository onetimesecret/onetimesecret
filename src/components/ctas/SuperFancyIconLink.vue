<script setup lang="ts">
defineProps<{
  text?: string;
  to: string;
  ariaLabel: string;
}>();
</script>

<template>
  <router-link
    :to="to"
    :aria-label="ariaLabel"
    class="glow-effect inline-flex items-center rounded-md px-2 py-1 text-sm
           font-medium
           text-white transition-all duration-300
           ease-in-out focus:outline-none focus:ring-2
           focus:ring-white">
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="mr-1 size-5 animate-pulse"
      viewBox="0 0 20 20"
      fill="currentColor">
      <path
        fill-rule="evenodd"
        d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z"
        clip-rule="evenodd" />
    </svg>
    <span
      v-if="text"
      class="animate-bounce">{{ text }}</span>
  </router-link>
</template>

<style scoped>
.glow-effect {
  background: linear-gradient(90deg, #ff00ff, #00ff00, #0000ff, #ff0000, #ff00ff);
  background-size: 400% 400%;
  animation: gradient 5s ease infinite, glow 1.5s ease-in-out infinite alternate;
  border: 2px solid transparent;
  background-clip: padding-box;
  box-shadow: 0 0 15px rgba(255, 255, 255, 0.5);
}

@keyframes gradient {
  0% { background-position: 0% 50%; }
  50% { background-position: 100% 50%; }
  100% { background-position: 0% 50%; }
}

@keyframes glow {
  from {
    box-shadow: 0 0 5px #fff, 0 0 10px #fff, 0 0 15px #fff, 0 0 20px #ff00de, 0 0 35px #ff00de, 0 0 40px #ff00de, 0 0 50px #ff00de, 0 0 75px #ff00de;
  }
  to {
    box-shadow: 0 0 2.5px #fff, 0 0 5px #fff, 0 0 7.5px #fff, 0 0 10px #ff00de, 0 0 17.5px #ff00de, 0 0 20px #ff00de, 0 0 25px #ff00de, 0 0 37.5px #ff00de;
  }
}
</style>
