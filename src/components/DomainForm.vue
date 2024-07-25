<template>
  <div class="space-y-9 my-32">
    <form>
      <DomainInput domain=""
                   :is-valid="true"
                   placeholder="e.g. secrets.example.com" />
      <button type="submit"
              class="hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-opacity-50 bg-brand-500 px-4 py-2 mt-4 text-lg text-white rounded">
        Add domain
      </button>

    </form>
  </div>
</template>

<script setup lang="ts">
import DomainInput from './DomainInput.vue';

</script>
