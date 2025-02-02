<script setup lang="ts">
// Directly copied from our site-policy repo:
// https://github.com/onetimesecret/site-policy/blob/main/onetime-terms-of-service.md
import Terms from '@/content/info/terms.md'

</script>

<template>
  <article class="prose">
    <h1 class="intro dark:text-gray-300">
      {{ $t('terms-of-service') }}
    </h1>

    <Terms class="prose prose-sm max-w-none dark:prose-invert sm:prose-base lg:prose-lg dark:text-gray-300" />
  </article>
</template>
