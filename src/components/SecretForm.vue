<script setup lang="ts">
</script>

<template>
  <main>
    <textarea
      class="w-full p-2 mb-4 border rounded dark:bg-gray-800 dark:border-gray-700"
      rows="6"
      placeholder="Secret content goes here..."
      aria-label="Secret content"></textarea>

    <div class="bg-gray-200 dark:bg-gray-800 p-4 rounded mb-4">
      <h2 class="text-lg font-bold mb-2">Privacy Options</h2>
      <div class="space-y-4">
        <div class="flex justify-between items-center">
          <label for="passphrase" class="w-1/3">Passphrase:</label>
          <input
            type="text"
            id="passphrase"
            class="w-2/3 p-2 border rounded dark:bg-gray-700 dark:border-gray-600"
            placeholder="A word or phrase that's difficult to guess">
        </div>
        <div class="flex justify-between items-center">
          <label for="recipient" class="w-1/3">Recipient Address:</label>
          <input
            type="email"
            id="recipient"
            class="w-2/3 p-2 border rounded dark:bg-gray-700 dark:border-gray-600"
            placeholder="example@onetimesecret.com">
        </div>
        <div class="flex justify-between items-center">
          <label for="lifetime" class="w-1/3">Lifetime:</label>
          <select
            id="lifetime"
            class="w-2/3 p-2 border rounded dark:bg-gray-700 dark:border-gray-600">
            <option>7 days</option>
            <!-- Add more options as needed -->
          </select>
        </div>
      </div>
    </div>

    <button
      class="w-full bg-orange-600 hover:bg-orange-700 text-white font-bold py-2 px-4 rounded mb-4">
      Create a secret link
    </button>

    <button
      class="w-full bg-gray-300 hover:bg-gray-400 dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-800 dark:text-gray-200 font-bold py-2 px-4 rounded mb-4">
      Or generate a random password
    </button>

    <div class="flex items-center space-x-2 mb-4">
      <input
        type="text"
        class="flex-grow p-2 border rounded dark:bg-gray-800 dark:border-gray-700"
        placeholder="Have a question or comment?">
      <button
        class="bg-gray-300 hover:bg-gray-400 dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-800 dark:text-gray-200 font-bold py-2 px-4 rounded">
        Send Feedback
      </button>
    </div>
  </main>
</template>
