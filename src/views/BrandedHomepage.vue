<script setup lang="ts">
  import SecretForm from '@/components/secrets/form/SecretForm.vue';

</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl py-1">


    <SecretForm class="mb-8"
                :with-recipient="false"
                :with-asterisk="false"
                :with-generate="false" />

  </div>
</template>
