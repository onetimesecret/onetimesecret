<script setup lang="ts">
import { ref } from 'vue';
import { Icon } from '@iconify/vue';

export interface Props {
  enabled?: boolean;
  shrimp: string | null;
  withRecipient?: boolean;
  withAsterisk?: boolean;
  withGenerate?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  enabled: true,
  shrimp: null,
  withRecipient: false,
  withAsterisk: false,
  withGenerate: false,
})

const showPassphrase = ref(false);
const currentPassphrase = ref('');

const togglePassphrase = () => {
  showPassphrase.value = !showPassphrase.value;
};

</script>

<template>
  <div class="">
    <form id="createSecret"
          method="post"
          autocomplete="off"
          action="/share"
          class="form-horizontal"
          :disabled="!props.enabled">
      <input type="hidden"
             name="utf8"
             value="✓" />
      <input type="hidden"
             name="shrimp"
             :value="shrimp" />
      <textarea class="w-full p-2 mb-4 border rounded dark:bg-gray-800 dark:border-gray-700"
                name="secret"
                rows="6"
                autofocus
                autocomplete="off"
                placeholder="Secret content goes here..."
                aria-label="Secret content"></textarea>

      <div class="bg-gray-100 dark:bg-gray-800 p-4 rounded mb-4">
        <h5 class="dark:text-white font-bold m-0 mb-4">Privacy Options</h5>
        <div class="space-y-4">
          <div class="flex justify-between items-center">
            <label for="currentPassphrase" class="w-1/3">Passphrase:</label>
            <div class="w-2/3 relative">
              <input
                :type="showPassphrase ? 'text' : 'password'"
                id="currentPassphrase"
                v-model="currentPassphrase"
                name="passphrase"
                autocomplete="unique-passphrase"
                placeholder="A word or passphrase that's difficult to guess"
                class="w-full p-2 border rounded dark:bg-gray-700 dark:border-gray-600 pr-10"
              >
              <button
                type="button"
                @click="togglePassphrase()"
                class="absolute inset-y-0 right-0 pr-3 flex items-center"
              >
                <Icon
                  :icon="showPassphrase ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
                  class="h-5 w-5 text-gray-400 dark:text-gray-100"
                  aria-hidden="true"
                />
              </button>
            </div>
          </div>

          <div v-if="props.withRecipient"
               class="flex justify-between items-center">
            <label for="recipient"
                   class="w-1/3">Recipient Address:</label>
            <input type="email"
                   id="recipient"
                   name="recipient[]"
                   class="w-2/3 p-2 border rounded dark:bg-gray-700 dark:border-gray-600"
                   placeholder="example@onetimesecret.com">
          </div>
          <div class="flex justify-between items-center">
            <label for="lifetime"
                   class="w-1/3">Lifetime:</label>
            <select id="lifetime"
                    name="ttl"
                    class="w-2/3 p-2 border rounded dark:bg-gray-700 dark:border-gray-600">
              <option value="1209600.0">14 days</option>
              <option value="604800.0"
                      selected>7 days</option>
              <option value="259200.0">3 days</option>
              <option value="86400.0">1 day</option>
              <option value="43200.0">12 hours</option>
              <option value="14400.0">4 hours</option>
              <option value="3600.0">1 hour</option>
              <option value="1800.0">30 minutes</option>
              <option value="300.0">5 minutes</option>

            </select>
          </div>
        </div>
      </div>

      <button type="submit"
              class="text-xl w-full py-2 px-4 rounded mb-4
              bg-orange-600 hover:bg-orange-700 text-white
              font-bold2 "
              name="kind"
              value="share">
        Create a secret link<span v-if="withAsterisk">*</span>
      </button>

      <button type="submit"
              v-if="props.withGenerate"
              class="w-full py-2 px-4 rounded mb-4
              text-base
              bg-gray-300 hover:bg-gray-400 text-gray-800
              dark:bg-gray-700 dark:hover:bg-gray-600 dark:text-gray-200"
              name="kind"
              value="generate">
        Or generate a random password
      </button>
    </form>
  </div>
</template>
