<template>
  <div class="flex items-center">
    <button @click="toggleDarkMode"
            aria-label="Toggle dark mode"
            :aria-pressed="isDarkMode"
            class="rounded-md hover:bg-gray-200 dark:hover:bg-gray-700 opacity-80 text-gray-400 dark:text-gray-400 transition-colors p-1">

      <svg v-if="isDarkMode"
           viewBox="0 0 24 24"
           fill="none"
           class="w-6 h-6">
        <path fill-rule="evenodd"
              clip-rule="evenodd"
              d="M17.715 15.15A6.5 6.5 0 0 1 9 6.035C6.106 6.922 4 9.645 4 12.867c0 3.94 3.153 7.136 7.042 7.136 3.101 0 5.734-2.032 6.673-4.853Z"
              class="fill-transparent"></path>
        <path d="m17.715 15.15.95.316a1 1 0 0 0-1.445-1.185l.495.869ZM9 6.035l.846.534a1 1 0 0 0-1.14-1.49L9 6.035Zm8.221 8.246a5.47 5.47 0 0 1-2.72.718v2a7.47 7.47 0 0 0 3.71-.98l-.99-1.738Zm-2.72.718A5.5 5.5 0 0 1 9 9.5H7a7.5 7.5 0 0 0 7.5 7.5v-2ZM9 9.5c0-1.079.31-2.082.845-2.93L8.153 5.5A7.47 7.47 0 0 0 7 9.5h2Zm-4 3.368C5 10.089 6.815 7.75 9.292 6.99L8.706 5.08C5.397 6.094 3 9.201 3 12.867h2Zm6.042 6.136C7.718 19.003 5 16.268 5 12.867H3c0 4.48 3.588 8.136 8.042 8.136v-2Zm5.725-4.17c-.81 2.433-3.074 4.17-5.725 4.17v2c3.552 0 6.553-2.327 7.622-5.537l-1.897-.632Z"
              class="fill-slate-400 dark:fill-slate-500"></path>
        <path fill-rule="evenodd"
              clip-rule="evenodd"
              d="M17 3a1 1 0 0 1 1 1 2 2 0 0 0 2 2 1 1 0 1 1 0 2 2 2 0 0 0-2 2 1 1 0 1 1-2 0 2 2 0 0 0-2-2 1 1 0 1 1 0-2 2 2 0 0 0 2-2 1 1 0 0 1 1-1Z"
              class="fill-slate-400 dark:fill-slate-500"></path>
      </svg>
      <svg v-else
           aria-hidden="true"
           class="w-6 h-6"
           fill="none"
           stroke="currentColor"
           viewBox="0 0 24 24"
           xmlns="http://www.w3.org/2000/svg">
        <path stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z">
        </path>
      </svg>
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'

const isDarkMode = ref(false)

const toggleDarkMode = () => {
  isDarkMode.value = !isDarkMode.value
  localStorage.setItem('restMode', isDarkMode.value.toString())
  updateDarkMode()
}

const updateDarkMode = () => {
  if (isDarkMode.value) {
    document.documentElement.classList.add('dark')
  } else {
    document.documentElement.classList.remove('dark')
  }
}

const detectSystemPreference = () => {
  return window.matchMedia('(prefers-color-scheme: dark)').matches
}

onMounted(() => {
  const storedPreference = localStorage.getItem('restMode')
  if (storedPreference !== null) {
    isDarkMode.value = storedPreference === 'true'
  } else {
    isDarkMode.value = detectSystemPreference()
  }
  updateDarkMode()
})

watch(isDarkMode, updateDarkMode)
</script>
