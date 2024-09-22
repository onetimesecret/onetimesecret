<template>
  <div>
    <header>
      <!-- Your header content -->

    </header>
    <main class="container mx-auto p-4 max-w-2xl">
      <slot></slot>
    </main>

    <footer>
      <!-- Your footer content -->

      <!-- Dark mode toggle in the bottom left corner -->
      <div class="fixed bottom-4 left-4 z-50">
        <div class="mt-2 text-slate-300">
          <ThemeToggle />
        </div>
      </div>

      <!-- Languages dropdown in the bottom right corner -->
      <div class="fixed text-left bottom-4 right-4 z-50 opacity-60 hover:opacity-100" aria-label="Change language">
        <div class="relative">

          <LanguageToggle
            :isDefaultLocale="false"
            currentLocale="en"
            :supportedLocales="['en', 'fr', 'es']"
          />

        </div>
      </div>


    </footer>
  </div>
</template>

<script setup lang="ts">

import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';

</script>
