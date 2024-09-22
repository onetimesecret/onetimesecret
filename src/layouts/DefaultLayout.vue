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

    </footer>
  </div>
</template>

<script lang="ts">
export default {
  name: 'DefaultLayout'
}
</script>
