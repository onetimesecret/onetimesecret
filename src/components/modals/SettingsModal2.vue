<template>
  <div class="fixed inset-0 z-50 overflow-y-auto bg-black/50 backdrop-blur-sm flex items-center justify-center" aria-labelledby="settings-modal" role="dialog" aria-modal="true">
    <div class="w-full max-w-md mx-auto bg-slate-800 dark:bg-slate-900 rounded-lg shadow-xl overflow-hidden transform transition-all sm:max-w-lg">
      <div class="px-6 py-4 flex justify-between items-center border-b border-slate-700">
        <h2 id="settings-modal" class="text-xl font-semibold text-white">Settings</h2>
        <button @click="closeModal" class="text-slate-400 hover:text-slate-300 transition-colors" aria-label="Close settings">
          <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <div class="px-6 py-4 space-y-6">
        <div>
          <h3 class="text-sm font-medium text-slate-300 mb-2">Appearance</h3>
          <button class="p-2 rounded-full bg-slate-700 text-slate-200 hover:bg-slate-600 transition-colors" aria-label="Toggle theme">
            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
            </svg>
          </button>
        </div>

        <div>
          <h3 class="text-sm font-medium text-slate-300 mb-2">Language</h3>
          <div class="relative">
            <select class="w-full bg-slate-700 border border-slate-600 text-slate-200 rounded-md py-2 pl-3 pr-10 appearance-none focus:outline-none focus:ring-2 focus:ring-orange-500">
              <option>English</option>
              <!-- Add more language options here -->
            </select>
            <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center px-2 text-slate-400">
              <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
              </svg>
            </div>
          </div>
        </div>

        <div>
          <h3 class="text-sm font-medium text-slate-300 mb-2">Jurisdiction</h3>
          <div class="relative">
            <select class="w-full bg-slate-700 border border-slate-600 text-slate-200 rounded-md py-2 pl-3 pr-10 appearance-none focus:outline-none focus:ring-2 focus:ring-orange-500">
              <option>United Kingdom</option>
              <!-- Add more jurisdiction options here -->
            </select>
            <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center px-2 text-slate-400">
              <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
              </svg>
            </div>
          </div>
        </div>

        <div>
          <h3 class="text-sm font-medium text-slate-300 mb-2">Notifications</h3>
          <div class="flex items-center justify-between">
            <span class="text-slate-200">Email notifications</span>
            <label class="relative inline-flex items-center cursor-pointer">
              <input type="checkbox" value="" class="sr-only peer">
              <div class="w-11 h-6 bg-slate-600 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-orange-500 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-orange-500"></div>
            </label>
          </div>
        </div>
      </div>

      <div class="px-6 py-4 bg-slate-700 flex justify-end">
        <button @click="closeModal" class="px-4 py-2 bg-orange-600 hover:bg-orange-700 text-white font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500 transition-colors">
          Done
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const closeModal = () => {
  // Implement close modal logic
};
</script>
