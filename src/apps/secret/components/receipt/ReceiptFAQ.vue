<!-- src/apps/secret/components/receipt/ReceiptFAQ.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { Receipt, ReceiptDetails } from '@/schemas/models';

  const { t } = useI18n();

  interface Props {
    record: Receipt;
    details: ReceiptDetails;
  }

  defineProps<Props>();
</script>

<template>
  <div>
    <!-- F.A.Q (if show_secret) -->
    <div
      v-if="details.show_secret"
      class="space-y-6 text-sm text-gray-600 dark:text-gray-400">
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-200">
          F.A.Q.
        </h3>
        <div class="rounded-md bg-blue-50 px-3 py-1 dark:bg-blue-900/20">
          {{ t('web.receipt.expires_in_record_natural_expiration', [record.natural_expiration]) }}
        </div>
      </div>

      <div class="space-y-4">
        <h4 class="font-semibold text-gray-900 dark:text-gray-100">
          {{
            t('web.receipt.core_security_features')
          }}
        </h4>

        <div
          class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200 dark:bg-gray-800/50 dark:ring-gray-700">
          <h5 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
            {{
              t('web.receipt.one_time_access')
            }}
          </h5>
          <p>{{ t('web.receipt.each_secret_can_only_be_viewed_once_after_viewin') }}</p>
        </div>

        <template v-if="details.has_passphrase">
          <div
            class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200 dark:bg-gray-800/50 dark:ring-gray-700">
            <h5 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
              {{
                t('web.receipt.passphrase_protection')
              }}
            </h5>
            <a
              href="https://en.wikipedia.org/wiki/Bcrypt"
              class="text-blue-600 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300">bcrypt</a>
            {{ t('web.receipt.and_never_stored_in_its_original_form_this_appro') }}
          </div>
        </template>

        <div
          class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200 dark:bg-gray-800/50 dark:ring-gray-700">
          <h5 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
            {{
              t('web.receipt.what_happens_when_i_burn_a_secret')
            }}
          </h5>
          <p>{{ t('web.receipt.burning_a_secret_permanently_deletes_it_before_a') }}</p>
        </div>

        <div
          class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200 dark:bg-gray-800/50 dark:ring-gray-700">
          <h5 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
            {{
              t('web.receipt.why_can_i_only_see_the_secret_value_once')
            }}
          </h5>
          <p>{{ t('web.receipt.we_display_the_value_for_you_so_that_you_can_ver') }}</p>
        </div>
      </div>
    </div>

    <!-- F.A.Q (if not show_secret) -->
    <div
      v-else
      class="space-y-6 text-sm text-gray-600 dark:text-gray-400">
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-200">
          F.A.Q.
        </h3>
        <div class="rounded-md bg-blue-50 px-3 py-1 dark:bg-blue-900/20">
          {{
            t('web.receipt.expires_in_record_natural_expiration_0', [record.natural_expiration])
          }}
        </div>
      </div>

      <template v-if="!details.show_secret_link">
        <div
          class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200 dark:bg-gray-800/50 dark:ring-gray-700">
          <h5 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
            {{
              t('web.receipt.lost_your_secret_link')
            }}
          </h5>
          <p>{{ t('web.receipt.for_security_reasons_we_cant_recover_lost_secret') }}</p>
        </div>
      </template>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200 dark:bg-gray-800/50 dark:ring-gray-700">
        <h5 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{
            t('web.receipt.how_does_secret_expiration_work')
          }}
        </h5>
        <p>
          {{
            t('web.receipt.your_secret_will_remain_available_for_record_nat', [
              record.natural_expiration,
            ])
          }}
        </p>
      </div>

      <div
        class="rounded-lg bg-gray-50 p-4 ring-1 ring-gray-200 dark:bg-gray-800/50 dark:ring-gray-700">
        <h5 class="mb-2 font-medium text-gray-900 dark:text-gray-100">
          {{
            t('web.receipt.whats_the_burn_feature')
          }}
        </h5>
        <p>{{ t('web.receipt.the_burn_feature_lets_you_permanently_delete_a_s') }}</p>
      </div>
    </div>
    <div class="mt-6 text-xs">
      <p>
        {{ t('web.receipt.have_more_questions_visit_our') }}
        <RouterLink
          to="/docs"
          class="text-blue-600 hover:text-blue-700 hover:underline dark:text-blue-400 dark:hover:text-blue-300">
          documentation
        </RouterLink>
        or
        <RouterLink
          to="/feedback"
          class="text-blue-600 hover:text-blue-700 hover:underline dark:text-blue-400 dark:hover:text-blue-300">
          {{ t('web.receipt.send_feedback') }}
        </RouterLink>.
      </p>
    </div>
  </div>
</template>
