<template>
  <div>
    <!-- Your header content -->
    <header>
      <div class="w-full h-1 bg-brand-500 fixed top-0 left-0"></div>

      <GlobalBroadcast :show="false" content="" />

    </header>
    <main class="container mx-auto p-4 max-w-2xl">
      <slot></slot>
    </main>

    <!-- Your footer content -->
    <div class="container mx-auto p-4 max-w-2xl">
      <footer class="min-w-[320px] text-sm text-center space-y-2">

        <div>
          <FeedbackForm :shrimp="shrimp" :showRedButton="false" />
        </div>

        <!-- Dark mode toggle in t  he bottom left corner -->
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

        <div class="text-gray-400 dark:text-gray-500 mt-4 pt-4">
          v{{onetimeVersion}}
        </div>

      </footer>
    </div>
  </div>
</template>

<script setup lang="ts">
import GlobalBroadcast from '@/components/GlobalBroadcast.vue';
import FeedbackForm from '@/components/FeedbackForm.vue';
import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';

const shrimp = window.shrimp;
const onetimeVersion = window.ot_version;

</script>
