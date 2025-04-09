<!-- src/components/secrets/form/SecretForm.vue -->
<script setup lang="ts">
  import { watch, onMounted, ref } from 'vue';
  // import { useRouter } from 'vue-router';
  import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import SecretContentInputArea from './SecretContentInputArea.vue';
  import { useSecretConcealer } from '@/composables/useSecretConcealer';
  import { useDomainDropdown } from '@/composables/useDomainDropdown';
  import { useProductIdentity } from '@/stores/identityStore';
  import CustomDomainPreview from './../../CustomDomainPreview.vue';
  import SecretLinksTable from '../SecretLinksTable.vue';
  import HomepageLinksPlaceholder from '../HomepageLinksPlaceholder.vue';
  import { nanoid } from 'nanoid';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import SplitButton from '@/components/SplitButton.vue';

  export interface Props {
    enabled?: boolean;
    withRecipient?: boolean;
    withAsterisk?: boolean;
    withGenerate?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    enabled: true,
    withRecipient: false,
    withAsterisk: false,
    withGenerate: false,
  });

  // const router = useRouter();
  const productIdentity = useProductIdentity();
  const passphraseVisible = ref(false);
  // const mode = ref<'write' | 'preview'>('write');
  const showFinalNotice = ref(false);
  const showProTip = ref(props.withAsterisk);

  const concealedMessages = ref<ConcealedMessage[]>([]);

  const { form, validation, operations, isSubmitting, submit } = useSecretConcealer({
    onSuccess: async (response) => {
      const newMessage: ConcealedMessage = {
        id: nanoid(),
        metadata_key: response.record.metadata.key,
        secret_key: response.record.secret.key,
        response,
        clientInfo: {
          hasPassphrase: !!form.passphrase,
          ttl: form.ttl,
          createdAt: new Date(),
        },
      };
      concealedMessages.value.unshift(newMessage);
      operations.reset();
      secretContentInput.value?.clearTextarea(); // Clear textarea
    },
  });

  const { availableDomains, selectedDomain, domainsEnabled, updateSelectedDomain } =
    useDomainDropdown();

  const expiryOptions = [
    { value: 7 * 24 * 3600, label: '7 days' },
    { value: 3 * 24 * 3600, label: '3 days' },
    { value: 24 * 3600, label: '1 day' },
    { value: 12 * 3600, label: '12 hours' },
    { value: 1 * 3600, label: '1 hour' },
  ];

  // Form submission handlers
  const handleConceal = () => submit('conceal');
  const secretContentInput = ref<{ clearTextarea: () => void } | null>(null);
  const togglePassphraseVisibility = () => {
    passphraseVisible.value = !passphraseVisible.value;
  };

  // Watch for domain changes and update form
  watch(selectedDomain, (domain) => {
    operations.updateField('share_domain', domain);
  });

  onMounted(() => {
    operations.updateField('share_domain', selectedDomain.value);
  });
</script>

<template>
  <div class="min-w-[320px] max-w-2xl mx-auto space-y-6">
    <!-- Enhanced Alert Display -->
    <BasicFormAlerts
      :errors="Array.from(validation.errors.values())"
      class="sticky top-4 z-50" />

    <form
      ref="form1"
      @submit.prevent="handleConceal"
      class="space-y-6">
      <div
        ref="div1"
        class="overflow-visible rounded-xl border border-gray-200 bg-white shadow-lg dark:border-gray-700 dark:bg-slate-900">
        <!-- Main Content Section -->
        <div class="p-6 space-y-6">
          <!-- Secret Input Section -->
          <SecretContentInputArea
            ref="secretContentInput"
            v-model:content="form.secret"
            :disabled="isSubmitting"
            @update:content="(content) => operations.updateField('secret', content)"
            class="bg-gray-50 dark:bg-slate-800/50 transition-colors focus-within:bg-white dark:focus-within:bg-slate-800" />

          <!-- Form Controls Section -->
          <div class="grid gap-6 md:grid-cols-2">
            <!-- Passphrase Field -->
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  name="key"
                  class="h-4 w-4 text-gray-400" />
              </div>
              <input
                :type="passphraseVisible ? 'text' : 'password'"
                v-model="form.passphrase"
                class="w-full rounded-lg border border-gray-200 bg-white pl-10 pr-10 py-2.5 text-sm text-gray-900 placeholder:text-gray-400 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500"
                :placeholder="$t('web.secrets.enterPassphrase')" />
              <button
                type="button"
                @click="togglePassphraseVisibility"
                class="absolute inset-y-0 right-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  :name="passphraseVisible ? 'solid-eye' : 'outline-eye-off'"
                  class="h-4 w-4 text-gray-400 hover:text-gray-600" />
              </button>
            </div>

            <!-- Expiry Selection -->
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  name="fire"
                  class="h-4 w-4 text-gray-400" />
              </div>
              <select
                v-model="form.ttl"
                class="w-full appearance-none rounded-lg border border-gray-200 bg-white pl-10 pr-10 py-2.5 text-sm text-gray-900 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-slate-800 dark:text-white">
                <option
                  v-for="option in expiryOptions"
                  :key="option.value"
                  :value="option.value">
                  {{ option.label }}
                </option>
              </select>
              <div class="pointer-events-none absolute inset-y-0 right-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  name="chevron-down"
                  class="h-4 w-4 text-gray-400" />
              </div>
            </div>
          </div>
        </div>

        <!-- Pro tip Section -->
        <div
          v-if="showProTip"
          class="flex items-start gap-3 p-4 bg-brandcomp-50 dark:bg-brandcomp-900/20">
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="mt-0.5 h-5 w-5 flex-shrink-0 text-brandcomp-600 dark:text-brandcomp-500" />
          <p class="text-sm text-brandcomp-700 dark:text-brandcomp-300">
            Your message will self-destruct after being viewed. The link can only be accessed once.
          </p>
        </div>

        <!-- Footer Section -->
        <div class="border-t border-gray-200 dark:border-gray-700">
          <!-- Actions Container -->
          <div class="px-6 py-4">
            <div class="flex flex-col sm:gap-4 sm:flex-row sm:items-center sm:justify-between">
              <!-- Domain Preview (grows to fill available space) -->
              <div class="order-1 sm:order-2 flex-grow min-w-0">
                <CustomDomainPreview
                  v-if="productIdentity.isCanonical"
                  :available-domains="availableDomains"
                  :with-domain-dropdown="domainsEnabled"
                  @update:selected-domain="updateSelectedDomain"
                  class="w-full" />
              </div>

              <!-- Action Button (maintains consistent width) -->
              <div class="order-2 sm:order-2 flex-shrink-0">
                <div class="mb-2">
                  <SplitButton :with-generate="props.withGenerate" />
                </div>
              </div>
            </div>

            <!-- Final Notice Section -->
            <div
              v-if="showFinalNotice"
              class="border-t border-gray-200 dark:border-gray-700">
              <div class="flex items-start gap-3 p-4 bg-brandcomp-50 dark:bg-brandcomp-900/20">
                <OIcon
                  collection="heroicons"
                  name="information-circle"
                  class="mt-0.5 h-5 w-5 flex-shrink-0 text-brandcomp-600 dark:text-brandcomp-500" />
                <p class="text-sm text-brandcomp-700 dark:text-brandcomp-300"> </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </form>

    <template v-if="concealedMessages.length > 0">
      <SecretLinksTable :concealedMessages="concealedMessages" />
    </template>
    <template v-else>
      <HomepageLinksPlaceholder
        title="No secrets yet"
        description="Create a secret above to get started." />
    </template>
  </div>
</template>
