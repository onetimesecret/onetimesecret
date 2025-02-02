<script setup lang="ts">

</script>


<template>
  <div class="mb-8">
    <svg
      class="mx-auto size-32 text-red-500 dark:text-red-400"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
      xmlns="http://www.w3.org/2000/svg"
      width="128"
      height="128">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
  </div>

  <h2 class="mb-4 text-3xl font-bold text-gray-800 dark:text-gray-200">
    {{ $t('t-web-common-oops-something-went-wrong', [$t('web.COMMON.oops')]) }}
  </h2>

  <p class="mb-6 text-lg text-gray-600 dark:text-gray-400">
    {{ $t('were-sorry-but-an-unexpected-error-occurred-whil') }}
  </p>

  <nav class="mb-8">
    <a
      href="/"
      class="inline-block rounded-lg bg-brand-500 px-6 py-3 text-white shadow-md transition-colors duration-300 hover:bg-brand-600 hover:shadow-lg dark:bg-brand-600 dark:hover:bg-brand-700">
      {{ $t('return-to-home') }}
    </a>
  </nav>
</template>
