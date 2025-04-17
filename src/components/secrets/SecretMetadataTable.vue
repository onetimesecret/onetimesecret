<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import SecretMetadataTableItem from '@/components/secrets/SecretMetadataTableItem.vue';
  import { MetadataRecords } from '@/schemas/api/endpoints';
  import { WindowService } from '@/services/window.service';
  import { ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  // We only use t in template through the v-bind
  const { t: $t } = useI18n();

  interface Props {
    notReceived: MetadataRecords[];
    received: MetadataRecords[];
    isLoading: boolean;
  }

  defineProps<Props>();

  // Get the site host for building share links
  const site_host = WindowService.get('site_host');

  // Track item being copied for feedback
  const copiedItemKey = ref<string | null>(null);

  // Create shareable link for an item
  const getShareLink = (item: MetadataRecords) => {
    const share_domain = item.share_domain ?? site_host;
    return `https://${share_domain}/secret/${item.key}`;
  };

  // Handle copying link to clipboard
  const handleCopy = async (item: MetadataRecords) => {
    try {
      await navigator.clipboard.writeText(getShareLink(item));
      copiedItemKey.value = item.key;

      // Reset copied state after 1.5 seconds
      setTimeout(() => {
        copiedItemKey.value = null;
      }, 1500);
    } catch (err) {
      console.error('Failed to copy link: ', err);
    }
  };
</script>

<template>
  <div
    class="space-y-8"
    v-cloak>
    <template v-if="isLoading">
      <!-- Add a loading indicator here -->
      <div class="text-justify">
        <p class="text-gray-600 dark:text-gray-400">
          {{ $t('loading_ellipses') }}
        </p>
      </div>
    </template>
    <template v-else>
      <section
        class="mb-8"
        aria-labelledby="not-received-heading">
        <!-- Table with not received secrets -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-if="notReceived && notReceived.length > 0"
          class="relative overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm
            dark:border-gray-700 dark:bg-slate-900">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
              <caption class="sr-only">
                {{ $t('web.dashboard.title_not_received') }}
              </caption>
              <thead class="bg-gray-50 dark:bg-slate-800">
                <tr>
                  <!-- prettier-ignore-attribute class -->
                  <th
                    scope="col"
                    class="px-6 py-2.5 text-left text-xs font-medium uppercase tracking-wider
                      text-gray-700 dark:text-gray-400">
                    {{ $t('web.COMMON.secret') }}
                  </th>
                  <!-- prettier-ignore-attribute class -->
                  <th
                    scope="col"
                    class="hidden px-6 py-2.5 text-left text-xs font-medium uppercase tracking-wider
                      text-gray-700 dark:text-gray-400 sm:table-cell">
                    {{ $t('web.LABELS.details') }}
                  </th>
                  <!-- prettier-ignore-attribute class -->
                  <th
                    scope="col"
                    class="px-6 py-2.5 text-right text-xs font-medium uppercase tracking-wider
                      text-gray-700 dark:text-gray-400">
                    {{ $t('web.LABELS.actions') }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                <!-- prettier-ignore-attribute class -->
                <tr
                  v-for="item in notReceived"
                  :key="item.key"
                  class="group border-b border-gray-200 transition-all duration-200
                    hover:bg-gray-50/80 dark:border-gray-700 dark:hover:bg-slate-800/70">
                  <td class="whitespace-nowrap px-6 py-4">
                    <SecretMetadataTableItem
                      :secret-metadata="item"
                      view="table-cell" />
                  </td>
                  <td class="hidden whitespace-nowrap px-6 py-4 sm:table-cell">
                    <div class="text-sm text-gray-600 dark:text-gray-400">
                      <span v-if="item.show_recipients">
                        {{ $t('web.COMMON.sent_to') }} {{ item.recipients }}
                      </span>
                      <span v-else>
                        <!-- Has a passphrase -->
                      </span>
                    </div>
                  </td>
                  <td class="whitespace-nowrap px-6 py-4 text-right">
                    <!-- TODO: We need the secret key in the list metadata endpoint to create the link -->
                    <div

                      class="flex justify-end space-x-2">
                      <!-- prettier-ignore-attribute class -->
                      <div
                        v-if="!item.is_destroyed && false"
                        class="group relative inline-block">
                        <!-- Open Secret Button -->
                        <a
                          :href="getShareLink(item)"
                          target="_blank"
                          class="flex items-center gap-2 rounded-t
                            bg-gray-100 px-3 py-1.5 text-sm font-medium
                            text-gray-700 transition-all hover:bg-gray-200
                            focus:outline-none focus:ring-2 focus:ring-gray-300 focus:ring-offset-2
                            dark:bg-gray-800/50 dark:text-gray-300 dark:hover:bg-gray-700/40">
                          <OIcon
                            collection="heroicons"
                            name="arrow-top-right-on-square"
                            class="size-4" />
                          <span class="sr-only">{{ $t('web.COMMON.view_secret') }}</span>
                        </a>
                        <!-- Copy Button with Tooltip -->
                        <div
                          class="relative">
                          <!-- prettier-ignore-attribute class -->
                          <button
                            @click="handleCopy(item)"
                            class="flex w-full items-center
                              gap-2 rounded-b border-gray-200 bg-gray-100 px-3 py-1.5 text-sm font-medium text-gray-700 transition-all
                              hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-300 focus:ring-offset-2
                              dark:border-gray-700/50 dark:bg-gray-800/50 dark:text-gray-300 dark:hover:bg-gray-700/40">
                            <OIcon
                              collection="heroicons"
                              :name="copiedItemKey === item.key ? 'check' : 'clipboard'"
                              class="size-4" />
                            <span class="sr-only">{{ $t('web.LABELS.copy_to_clipboard') }}</span>
                          </button>
                          <!-- Copy Feedback Tooltip -->
                          <!-- prettier-ignore-attribute class -->
                          <div
                            v-if="copiedItemKey === item.key"
                            class="absolute -top-8 left-1/2 z-10 -translate-x-1/2 whitespace-nowrap
                            rounded-t bg-gray-800
                            px-2 py-1 text-xs text-white shadow-lg">
                            {{ $t('web.STATUS.copied') }}
                            <div
                              class="absolute left-1/2 top-full size-2 -translate-x-1/2
                              rotate-45 rounded-b bg-gray-800"></div>
                          </div>
                        </div>
                      </div>

                      <!-- prettier-ignore-attribute class -->
                      <router-link
                        v-if="!item.is_destroyed"
                        :to="{ name: 'Burn secret', params: { metadataKey: item.key } }"
                        class="inline-flex items-center rounded-md bg-red-100 px-2.5 py-1.5 text-sm
                          font-medium text-red-700 hover:bg-red-200 focus:outline-none focus:ring-2
                          focus:ring-red-500 focus:ring-offset-2 dark:bg-red-900/30 dark:text-red-300
                          dark:hover:bg-red-800/40">
                        <OIcon
                          collection="heroicons"
                          name="fire"
                          class="mr-1.5 size-4" />
                        <span>{{ $t('web.COMMON.burn') }}</span>
                      </router-link>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Empty state for not received -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-else
          class="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center
            dark:border-gray-700 dark:bg-slate-800/30">
          <div class="flex flex-col items-center justify-center">
            <OIcon
              collection="heroicons"
              name="document-text"
              class="mb-3 size-10 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
            <p class="text-gray-600 dark:text-gray-400">
              {{ $t('go-on-then') }}
              <router-link
                to="/"
                class="text-brand-500 hover:underline">
                {{ $t('web.COMMON.share_a_secret') }}
              </router-link>
            </p>
          </div>
        </div>
      </section>

      <!-- Received Secrets Section -->
      <section
        class="mb-8"
        aria-labelledby="received-heading">
        <h3
          id="received-heading"
          class="mb-4 text-xl font-medium text-gray-700 dark:text-gray-200">
          {{ $t('web.dashboard.title_received') }}
        </h3>

        <!-- Table with received secrets -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-if="received && received.length > 0"
          class="relative overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm
            dark:border-gray-700 dark:bg-slate-900">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
              <caption class="sr-only">
                {{ $t('web.dashboard.title_received') }}
              </caption>
              <thead class="bg-gray-50 dark:bg-slate-800">
                <tr>
                  <!-- prettier-ignore-attribute class -->
                  <th
                    scope="col"
                    class="px-6 py-2.5 text-left text-xs font-medium uppercase tracking-wider
                      text-gray-700 dark:text-gray-400">
                    {{ $t('web.COMMON.secret') }}
                  </th>
                  <!-- prettier-ignore-attribute class -->
                  <th
                    scope="col"
                    class="hidden px-6 py-2.5 text-left text-xs font-medium uppercase tracking-wider
                      text-gray-700 dark:text-gray-400 sm:table-cell">
                    {{ $t('web.LABELS.details') }}
                  </th>
                  <!-- prettier-ignore-attribute class -->
                  <th
                    scope="col"
                    class="px-6 py-2.5 text-right text-xs font-medium uppercase tracking-wider
                      text-gray-700 dark:text-gray-400">
                    {{ $t('status') }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                <!-- prettier-ignore-attribute class -->
                <tr
                  v-for="item in received"
                  :key="item.key"
                  class="group border-b border-gray-200 transition-all duration-200
                    hover:bg-gray-50/80 dark:border-gray-700 dark:hover:bg-slate-800/70">
                  <td class="whitespace-nowrap px-6 py-4">
                    <SecretMetadataTableItem
                      :secret-metadata="item"
                      view="table-cell" />
                  </td>
                  <td class="hidden whitespace-nowrap px-6 py-4 sm:table-cell">
                    <div class="text-sm text-gray-600 dark:text-gray-400">
                      <span v-if="item.show_recipients">
                        {{ $t('web.COMMON.sent_to') }} {{ item.recipients }}
                      </span>
                    </div>
                  </td>
                  <td class="whitespace-nowrap px-6 py-4 text-right">
                    <span
                      :class="[
                        'inline-flex items-center rounded-md px-2.5 py-1.5 text-sm font-medium',
                        item.is_destroyed
                          ? 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300'
                          : item.is_burned
                            ? 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300'
                            : 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300',
                      ]">
                      <OIcon
                        :collection="'heroicons'"
                        :name="item.is_burned ? 'fire' : 'x-mark' "
                        size="4"
                        class="mr-1.5" />
                      <span v-if="item.is_expired">
                        {{ $t('web.STATUS.expired') }}
                      </span>
                      <span v-else-if="item.is_burned">
                        {{ $t('web.STATUS.burned') }}
                      </span>
                      <span v-else>
                        {{ $t('web.STATUS.received') }}
                      </span>
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Empty state for received -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-else
          class="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center
            dark:border-gray-700 dark:bg-slate-800/30">
          <div class="flex flex-col items-center justify-center">
            <OIcon
              collection="heroicons"
              name="inbox"
              class="mb-3 size-10 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
            <p class="text-gray-600 dark:text-gray-400">
              {{ $t('web.COMMON.word_none') }}
            </p>
          </div>
        </div>
      </section>
    </template>
  </div>
</template>
