<script setup lang="ts">

export interface Props {
  enabled?: boolean;
  shrimp: string | null | undefined;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const props = withDefaults(defineProps<Props>(), {
  enabled: true,
})

</script>

<template>


  <form id="createSecret"
        method="post"
        autocomplete="off"
        action="/incoming"
        class="space-y-6">
    <input type="hidden"
           name="shrimp"
           :value="shrimp" />
    <div>
      <textarea rows="7"
                class="w-full px-3 py-2 text-gray-700 dark:text-gray-300 border rounded-lg focus:outline-none dark:bg-gray-700 dark:border-gray-600 focus:ring-brandcomp-500 focus:border-brandcomp-500 "
                name="secret"
                autocomplete="off"
                placeholder="{{i18n.page.incoming_secret_placeholder}}"></textarea>
    </div>

    <div class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
      <h3 class="text-lg font-medium text-gray-900 dark:text-white mb-4">{{ i18n.page.incoming_secret_options }}</h3>

      <div class="space-y-4">
        <div>
          <label for="ticketnoField"
                 class="block text-sm font-medium text-gray-700 dark:text-gray-300">{{ i18n.page.incoming_ticket_number }}:</label>
          <input type="text"
                 name="ticketno"
                 id="ticketnoField"
                 class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-brandcomp-500 focus:border-brandcomp-500 sm:text-sm dark:bg-gray-600 dark:border-gray-500 dark:text-white"
                 placeholder="{{i18n.page.incoming_ticket_number_hint}}"
                 autocomplete="off" />
        </div>

        <div>
          <label for="recipientField"
                 class="block text-sm font-medium text-gray-700 dark:text-gray-300">{{ i18n.page.incoming_recipient_address }}:</label>
          <div class="mt-1 text-sm text-gray-900 dark:text-gray-100">{{ incoming_recipient }}</div>
        </div>
      </div>
    </div>

    <button type="submit"
            name="kind"
            value="share"
            class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:bg-brand-500 dark:hover:bg-brand-600 dark:focus:ring-offset-gray-800">
      {{ i18n.page.incoming_button_create }}
    </button>
  </form>

  <script>
    document.querySelector('#createSecret textarea').addEventListener('keyup', function () {
      const max = {{plan.options.size}};
      const len = this.value.length;
      const obj = document.querySelector('#createSecret .chars-display');
      if (len > max && obj.classList.contains('text-gray-500')) {
        obj.classList.remove('text-gray-500', 'dark:text-gray-400');
        obj.classList.add('text-red-500', 'dark:text-red-400');
      } else if (len <= max && obj.classList.contains('text-red-500')) {
        obj.classList.remove('text-red-500', 'dark:text-red-400');
        obj.classList.add('text-gray-500', 'dark:text-gray-400');
      }
      const char = max - len;
      obj.textContent = char;
      const sub = document.querySelector('#createSecret .generate');
      if (len > 0 && !sub.disabled) {
        sub.disabled = true;
      }
      if (len == 0) {
        sub.disabled = false;
      }
    });
  </script>


</template>
