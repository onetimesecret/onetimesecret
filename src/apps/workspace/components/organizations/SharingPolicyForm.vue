<script setup lang="ts">
  import type { SharingPolicy } from '@/schemas/contracts/sharing-policy';
  import { classifyError } from '@/schemas/errors';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import SettingsCard from '@/shared/components/ui/SettingsCard.vue';
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
    form: `${uid}-form`,
    mode: `${uid}-mode`,
    domains: `${uid}-domains`,
    domainsHint: `${uid}-domains-hint`,
    passphrase: `${uid}-passphrase`,
    ttl: `${uid}-ttl`,
    ttlHint: `${uid}-ttl-hint`,
  };

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
  <SettingsCard
    :title="t('web.organizations.sharing_policy.title')"
    :description="t('web.organizations.sharing_policy.description')"
    :heading-level="3"
    variant="glass">
    <form
      :id="ids.form"
      @submit.prevent="save">
      <fieldset
        :disabled="saving"
        class="min-w-0">
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
              class="block field-label">
              {{ t('web.organizations.sharing_policy.recipient_email') }}
            </label>
            <select
              :id="ids.mode"
              v-model="mode"
              class="mt-1 field-input">
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
              class="block field-label">
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
              class="mt-1 field-input font-mono"></textarea>
            <p
              :id="ids.domainsHint"
              class="mt-1 field-hint">
              {{ t('web.organizations.sharing_policy.domains_hint') }}
            </p>
          </div>

          <div class="flex items-center gap-3">
            <input
              :id="ids.passphrase"
              v-model="required"
              type="checkbox"
              class="field-check rounded" />
            <label
              :for="ids.passphrase"
              class="field-label">
              {{ t('web.organizations.sharing_policy.require_passphrase') }}
            </label>
          </div>

          <div class="sm:max-w-md">
            <label
              :for="ids.ttl"
              class="block field-label">
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
              class="mt-1 field-input tabular-nums" />
            <p
              :id="ids.ttlHint"
              class="mt-1 field-hint">
              {{ t('web.organizations.sharing_policy.ttl_hint') }}
            </p>
          </div>
        </div>
      </fieldset>
    </form>

    <!-- The button sits in the card footer, outside the form element, so it
         names the form it submits and carries the saving state itself. -->
    <template #footer>
      <button
        type="submit"
        :form="ids.form"
        :disabled="!changed || saving"
        class="btn-primary">
        {{ saving ? t('web.COMMON.saving') : t('web.COMMON.save_changes') }}
      </button>
    </template>
  </SettingsCard>
</template>
