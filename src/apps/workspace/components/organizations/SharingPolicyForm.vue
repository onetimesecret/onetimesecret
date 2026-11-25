<script setup lang="ts">
  import type { SharingPolicy } from '@/schemas/contracts/sharing-policy';
  import { classifyError } from '@/schemas/errors';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import type { Organization } from '@/types/organization';
  import { computed, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  const props = defineProps<{ extid: string; policy: SharingPolicy }>();
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

  const changed = computed(() => {
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
  <form
    class="space-y-4 rounded-lg border border-gray-200 bg-white p-6
           dark:border-gray-700 dark:bg-gray-800"
    @submit.prevent="save">
    <h3 class="text-base font-semibold">
      {{ t('web.organizations.sharing_policy.title') }}
    </h3>
    <BasicFormAlerts
      v-if="error || success"
      :error="error"
      :success="success" />

    <fieldset class="space-y-4" :disabled="saving">
      <label class="block text-sm font-medium">
        {{ t('web.organizations.sharing_policy.recipient_email') }}
        <select v-model="mode" class="mt-1 block w-full rounded-md dark:bg-gray-700">
          <option value="unrestricted">{{ t('web.organizations.sharing_policy.unrestricted') }}</option>
          <option value="restricted">{{ t('web.organizations.sharing_policy.restricted') }}</option>
          <option value="disabled">{{ t('web.organizations.sharing_policy.disabled') }}</option>
        </select>
      </label>
      <label v-if="mode === 'restricted'" class="block text-sm font-medium">
        {{ t('web.organizations.sharing_policy.domains') }}
        <textarea
          v-model="domains"
          rows="3"
          required
          class="mt-1 block w-full rounded-md dark:bg-gray-700"></textarea>
        <span class="mt-1 block text-xs">
          {{ t('web.organizations.sharing_policy.domains_hint') }}
        </span>
      </label>
      <label class="flex items-center gap-2 text-sm font-medium">
        <input
          v-model="required"
          type="checkbox"
          class="rounded text-brand-600" />
        {{ t('web.organizations.sharing_policy.require_passphrase') }}
      </label>
      <label class="block text-sm font-medium">
        {{ t('web.organizations.sharing_policy.max_ttl') }}
        <input
          v-model.number="maxTtl"
          type="number"
          min="60"
          step="1"
          class="mt-1 block w-full rounded-md dark:bg-gray-700" />
        <span class="mt-1 block text-xs">{{ t('web.organizations.sharing_policy.ttl_hint') }}</span>
      </label>
      <button
        type="submit"
        :disabled="!changed"
        class="rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white
               hover:bg-brand-500 disabled:opacity-50">
        {{ saving ? t('web.COMMON.saving') : t('web.COMMON.save_changes') }}
      </button>
    </fieldset>
  </form>
</template>
