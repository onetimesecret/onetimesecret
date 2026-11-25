<script setup lang="ts">
  import type { SharingPolicy } from '@/schemas/contracts/sharing-policy';
  import { classifyError } from '@/schemas/errors';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import type { Organization } from '@/types/organization';
  import { computed, ref, useId, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  const props = defineProps<{ extid: string; policy: SharingPolicy; invalid?: boolean }>();
  const emit = defineEmits<{ saved: [organization: Organization] }>();
  const { t } = useI18n();
  const store = useOrganizationStore();
  const mode = ref(props.policy.recipient_email_mode);
  const domains = ref('');
  const required = ref(false);
  const maxTtl = ref<number | ''>('');
  const saving = ref(false);
  const error = ref('');
  const success = ref('');

  const uid = useId();
  const ids = {
    mode: `${uid}-mode`,
    domains: `${uid}-domains`,
    domainsHint: `${uid}-domains-hint`,
    passphrase: `${uid}-passphrase`,
    ttl: `${uid}-ttl`,
    ttlHint: `${uid}-ttl-hint`,
  };

  // Shared by the select, textarea and number input. scheme-dark makes the
  // browser draw the select popup and the number spinner for a dark surface.
  const controlClass =
    'mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 sm:text-sm dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:scheme-dark';
  const labelClass = 'block text-sm font-medium text-gray-700 dark:text-gray-300';
  const hintClass = 'mt-1 text-xs text-gray-500 dark:text-gray-400';

  watch(() => props.policy, (policy) => {
    mode.value = policy.recipient_email_mode;
    domains.value = policy.recipient_email_domains.join('\n');
    required.value = policy.passphrase_required;
    maxTtl.value = policy.max_ttl ?? '';
  }, { immediate: true });

  const draftPolicy = computed<SharingPolicy>(() => ({
    recipient_email_mode: mode.value,
    recipient_email_domains: domains.value.split(/[\s,]+/).filter(Boolean),
    passphrase_required: required.value,
    max_ttl: maxTtl.value === '' ? null : maxTtl.value,
  }));

  // An unreadable stored policy is shown as the strictest policy. Saving it
  // unchanged still replaces the stored value, so allow that.
  const changed = computed(() => {
    if (props.invalid) return true;
    const saved = props.policy;
    const draft = draftPolicy.value;
    return saved.recipient_email_mode !== draft.recipient_email_mode ||
      saved.passphrase_required !== draft.passphrase_required || saved.max_ttl !== draft.max_ttl ||
      saved.recipient_email_domains.join('\n') !== draft.recipient_email_domains.join('\n');
  });

  async function save() {
    if (saving.value || !changed.value) return;
    saving.value = true;
    error.value = '';
    success.value = '';
    try {
      const updated = await store.updateSharingPolicy(props.extid, draftPolicy.value);
      emit('saved', updated);
      success.value = t('web.organizations.update_success');
    } catch (err) {
      error.value = classifyError(err).message || t('web.organizations.update_error');
    } finally {
      saving.value = false;
    }
  }
</script>

<template>
  <section
    class="rounded-lg border border-gray-200/60 bg-white/60 shadow-sm backdrop-blur-sm dark:border-gray-700/60 dark:bg-gray-800/60">
    <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
      <h3 class="text-base font-semibold text-gray-900 dark:text-white">
        {{ t('web.organizations.sharing_policy.title') }}
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.organizations.sharing_policy.description') }}
      </p>
    </div>

    <form @submit.prevent="save">
      <fieldset
        :disabled="saving"
        class="min-w-0">
        <div class="p-6">
          <BasicFormAlerts
            v-if="error || success"
            :error="error"
            :success="success" />
          <p
            v-if="invalid"
            role="alert"
            data-testid="sharing-policy-invalid"
            class="mb-6 rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-800/50 dark:bg-amber-900/30 dark:text-amber-200">
            {{ t('web.organizations.sharing_policy.invalid_notice') }}
          </p>

          <div class="space-y-6">
            <div class="sm:max-w-md">
              <label
                :for="ids.mode"
                :class="labelClass">
                {{ t('web.organizations.sharing_policy.recipient_email') }}
              </label>
              <select
                :id="ids.mode"
                v-model="mode"
                :class="controlClass">
                <option value="unrestricted">
                  {{ t('web.organizations.sharing_policy.unrestricted') }}
                </option>
                <option value="restricted">
                  {{ t('web.organizations.sharing_policy.restricted') }}
                </option>
                <option value="disabled">
                  {{ t('web.organizations.sharing_policy.disabled') }}
                </option>
              </select>
            </div>

            <div
              v-if="mode === 'restricted'"
              class="sm:max-w-md">
              <label
                :for="ids.domains"
                :class="labelClass">
                {{ t('web.organizations.sharing_policy.domains') }}
              </label>
              <textarea
                :id="ids.domains"
                v-model="domains"
                rows="3"
                required
                spellcheck="false"
                autocapitalize="off"
                :aria-describedby="ids.domainsHint"
                :class="[controlClass, 'font-mono']"></textarea>
              <p
                :id="ids.domainsHint"
                :class="hintClass">
                {{ t('web.organizations.sharing_policy.domains_hint') }}
              </p>
            </div>

            <div class="flex items-center gap-3">
              <input
                :id="ids.passphrase"
                v-model="required"
                type="checkbox"
                class="size-4 rounded border-gray-300 text-brand-600 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:ring-offset-gray-800" />
              <label
                :for="ids.passphrase"
                class="text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.organizations.sharing_policy.require_passphrase') }}
              </label>
            </div>

            <div class="sm:max-w-md">
              <label
                :for="ids.ttl"
                :class="labelClass">
                {{ t('web.organizations.sharing_policy.max_ttl') }}
              </label>
              <input
                :id="ids.ttl"
                v-model.number="maxTtl"
                type="number"
                min="60"
                step="1"
                inputmode="numeric"
                :aria-describedby="ids.ttlHint"
                :class="[controlClass, 'tabular-nums']" />
              <p
                :id="ids.ttlHint"
                :class="hintClass">
                {{ t('web.organizations.sharing_policy.ttl_hint') }}
              </p>
            </div>
          </div>
        </div>

        <div
          class="flex items-center justify-end border-t border-gray-200 px-6 py-4 dark:border-gray-700">
          <button
            type="submit"
            :disabled="!changed"
            class="rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
            {{ saving ? t('web.COMMON.saving') : t('web.COMMON.save_changes') }}
          </button>
        </div>
      </fieldset>
    </form>
  </section>
</template>
