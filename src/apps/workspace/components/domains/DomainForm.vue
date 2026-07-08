<!-- src/apps/workspace/components/domains/DomainForm.vue -->

<script setup lang="ts">
  import DomainInput from '@/apps/workspace/components/domains/DomainInput.vue';
  import { addDomainRequestSchema } from '@/schemas/api/domains/requests';
  import { analyzeDomain } from '@/utils/parse/domain';
  import { ref, computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  defineProps<{
    isSubmitting?: boolean;
  }>();

  const emit = defineEmits<{
    (e: 'submit', domain: string): void;
    (e: 'back'): void;
  }>();

  const { t } = useI18n();

  // The address the user picks for an apex domain, or 'root' to point the whole
  // registrable at us. `null` until the user chooses (apex only).
  type Choice = 'secrets' | 'links' | 'secure' | 'share' | 'root' | null;
  const SUBS = ['secrets', 'links', 'secure', 'share'] as const;

  const raw = ref('');
  const choice = ref<Choice>(null);
  // Gates every inline error: nothing complains until the user tries to submit.
  const attempted = ref(false);

  const analysis = computed(() => analyzeDomain(raw.value));

  // Any keystroke invalidates the current guidance: drop the pending choice and
  // reset the attempted flag so stale errors clear immediately.
  const onInput = (value: string) => {
    raw.value = value;
    choice.value = null;
    attempted.value = false;
  };

  // A deeper hostname (secrets.acme.com): we use it verbatim, just confirm it.
  const showEcho = computed(() => analysis.value.valid && !analysis.value.apex);
  // A bare registrable (acme.com / acme.co.uk): make the user pick where links live.
  const showCards = computed(() => analysis.value.valid && analysis.value.apex);
  // A non-empty, unusable hostname after a submit attempt.
  const showError = computed(
    () => attempted.value && !analysis.value.empty && !analysis.value.valid
  );
  // An empty submit attempt keeps the original "please enter a domain" copy.
  const showEmptyError = computed(() => attempted.value && analysis.value.empty);
  const needsChoice = computed(() => showCards.value && !choice.value);

  // The single string the API receives. '' whenever we cannot yet build one.
  const finalHost = computed(() => {
    const a = analysis.value;
    if (!a.valid) return '';
    if (!a.apex) return a.full;
    if (choice.value === 'root') return a.registrable;
    return choice.value ? `${choice.value}.${a.registrable}` : '';
  });

  // Only paint the field red for a real hostname problem, never for empty.
  const inputValid = computed<boolean | null>(() => (showError.value ? false : null));

  // The input is always described by the help text; when an inline error is
  // showing, add the error element so screen readers announce it too.
  const describedby = computed(() =>
    showEmptyError.value || showError.value ? 'domain-help domain-error' : 'domain-help'
  );

  const placeholderText = computed(
    () => `${t('web.COMMON.e_g_example')} ${t('web.domains.secrets_example_dot_com')}`
  );

  const errorMessage = computed(() => {
    const a = analysis.value;
    if (a.reason === 'suffix' && a.full.includes('.')) {
      return t('web.domains.add.error_unrecognized_suffix', [a.tld, 'secrets.acme.com']);
    }
    return t('web.domains.add.error_invalid_hostname', ['secrets.acme.com']);
  });

  const continueLabel = computed(() => {
    if (!analysis.value.valid) return t('web.domains.add_domain');
    if (showCards.value && !choice.value) return t('web.COMMON.continue');
    return t('web.domains.add.continue_with', [finalHost.value]);
  });

  const handleSubmit = () => {
    attempted.value = true;

    const a = analysis.value;
    // Empty and invalid both surface an inline error and stop here.
    if (a.empty || !a.valid) return;
    // Apex with no address chosen yet — the button is disabled, but guard anyway.
    if (showCards.value && !choice.value) return;

    const host = finalHost.value;
    try {
      // Belt-and-suspenders: the server is authoritative, but re-run the same
      // request-schema guard the API uses before we emit.
      const validated = addDomainRequestSchema.parse({ domain: host });
      emit('submit', validated.domain);
    } catch (err) {
      // A valid analysis always satisfies the schema; if it somehow doesn't we
      // simply don't emit rather than sending a bad domain upstream. Surface it
      // in development so the divergence is debuggable.
      if (import.meta.env.DEV) console.error('[DomainForm] unexpected schema rejection', err);
    }
  };
</script>

<template>
  <div class="mx-auto my-16 max-w-full space-y-10 px-4 sm:px-6 lg:px-8 dark:bg-gray-900">
    <form
      @submit.prevent="handleSubmit"
      data-testid="domain-add-form"
      class="space-y-6">
      <!-- Step rail: reflects the real Add › Verify › Brand flow -->
      <nav
        :aria-label="t('web.domains.add.step_rail_label')"
        class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
        <span class="font-medium text-brand-600 dark:text-brand-400">
          1 {{ t('web.domains.add.step_add') }}
        </span>
        <span
          aria-hidden="true"
          class="text-gray-400 dark:text-gray-500">›</span>
        <span class="text-gray-500 dark:text-gray-400">
          2 {{ t('web.domains.add.step_verify') }}
        </span>
        <span
          aria-hidden="true"
          class="text-gray-400 dark:text-gray-500">›</span>
        <span class="text-gray-500 dark:text-gray-400">
          3 {{ t('web.domains.add.step_brand') }}
        </span>
      </nav>

      <!-- Field: visible label + raw input + help text -->
      <div class="space-y-2">
        <label
          for="domain"
          class="block text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.add.field_label') }}
        </label>
        <DomainInput
          :model-value="raw"
          @update:model-value="onInput"
          :is-valid="inputValid"
          :describedby="describedby"
          autofocus
          data-testid="domain-input"
          :placeholder="placeholderText"
          class="dark:border-gray-700 dark:bg-gray-800 dark:text-white" />
        <p
          id="domain-help"
          class="text-xs text-gray-500 dark:text-gray-400">
          <i18n-t
            keypath="web.domains.add.field_help"
            tag="span"
            scope="global">
            <template #example>
              <span class="font-mono text-gray-700 dark:text-gray-300">secrets.example.com</span>
            </template>
          </i18n-t>
        </p>
      </div>

      <!-- Echo: confirm a deeper hostname we will use verbatim -->
      <div
        v-if="showEcho"
        data-testid="domain-echo"
        class="rounded-lg border border-gray-200 bg-gray-50 p-3 dark:border-gray-700 dark:bg-gray-800/50">
        <p class="text-xs tracking-wide text-gray-500 uppercase dark:text-gray-400">
          {{ t('web.domains.add.echo_label') }}
        </p>
        <p class="mt-1 font-mono text-sm break-all text-gray-900 dark:text-white">
          https://{{ analysis.full }}/secret/…
        </p>
      </div>

      <!-- Apex chooser: pick where secret links live on a bare registrable -->
      <fieldset
        v-if="showCards"
        data-testid="domain-apex-cards"
        class="space-y-3">
        <legend class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.add.apex_question') }}
        </legend>
        <p class="text-xs text-gray-500 dark:text-gray-400">
          <i18n-t
            keypath="web.domains.add.apex_help"
            tag="span"
            scope="global">
            <template #domain>
              <span class="font-mono text-gray-700 dark:text-gray-300">{{ analysis.registrable }}</span>
            </template>
          </i18n-t>
        </p>

        <div
          role="radiogroup"
          :aria-label="t('web.domains.add.apex_question')"
          class="space-y-2">
          <!-- Subdomain options -->
          <label
            v-for="sub in SUBS"
            :key="sub"
            :data-testid="`domain-address-option-${sub}`"
            :class="[
              'flex cursor-pointer items-center gap-3 rounded-lg border p-3 transition-colors focus-within:ring-2 focus-within:ring-brand-500',
              choice === sub
                ? 'border-brand-500 bg-brand-50/50 dark:border-brand-400 dark:bg-brand-900/10'
                : 'border-gray-200 hover:border-gray-300 hover:bg-gray-50 dark:border-gray-700 dark:hover:border-gray-600 dark:hover:bg-gray-700/30',
            ]">
            <input
              v-model="choice"
              type="radio"
              name="apex-address"
              :value="sub"
              class="size-4 shrink-0 accent-brand-600 focus:outline-none dark:accent-brand-400" />
            <span class="min-w-0 flex-1 font-mono text-sm break-all text-gray-900 dark:text-white">
              {{ sub }}.{{ analysis.registrable }}
            </span>
            <span
              v-if="sub === 'secrets'"
              class="shrink-0 rounded-full bg-brand-50 px-2 py-0.5 text-[10px] font-medium tracking-wide text-brand-700 uppercase ring-1 ring-brand-600/20 ring-inset dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30">
              {{ t('web.domains.add.recommended') }}
            </span>
          </label>

          <!-- Divider before the higher-consequence root option -->
          <div
            class="border-t border-gray-200 dark:border-gray-700"
            aria-hidden="true"></div>

          <!-- Root domain: heads-up, amber-toned caution treatment -->
          <label
            data-testid="domain-root-option"
            :class="[
              'flex cursor-pointer items-start gap-3 rounded-lg border p-3 transition-colors focus-within:ring-2 focus-within:ring-brand-500',
              choice === 'root'
                ? 'border-brand-500 bg-brand-50/50 dark:border-brand-400 dark:bg-brand-900/10'
                : 'border-gray-200 hover:border-gray-300 hover:bg-gray-50 dark:border-gray-700 dark:hover:border-gray-600 dark:hover:bg-gray-700/30',
            ]">
            <input
              v-model="choice"
              type="radio"
              name="apex-address"
              value="root"
              class="mt-0.5 size-4 shrink-0 accent-brand-600 focus:outline-none dark:accent-brand-400" />
            <span class="min-w-0 flex-1">
              <span class="block font-mono text-sm break-all text-gray-900 dark:text-white">
                {{ analysis.registrable }}
              </span>
              <span class="mt-1 block text-sm font-medium text-amber-600 dark:text-amber-400">
                {{ t('web.domains.add.root_domain_label') }}
              </span>
              <span class="mt-0.5 block text-xs text-amber-600/90 dark:text-amber-400/90">
                <i18n-t
                  keypath="web.domains.add.root_domain_description"
                  tag="span"
                  scope="global">
                  <template #domain>
                    <span class="font-mono">{{ analysis.registrable }}</span>
                  </template>
                </i18n-t>
              </span>
            </span>
          </label>
        </div>
      </fieldset>

      <!-- Inline error: empty submit keeps the original copy; otherwise hostname guidance -->
      <p
        v-if="showEmptyError"
        id="domain-error"
        role="alert"
        data-testid="domain-error"
        class="text-sm text-red-600 dark:text-red-400">
        {{ t('web.domains.add.error_empty') }}
      </p>
      <p
        v-else-if="showError"
        id="domain-error"
        role="alert"
        data-testid="domain-error"
        class="text-sm text-red-600 dark:text-red-400">
        {{ errorMessage }}
      </p>

      <div
        class="flex flex-col-reverse
        space-y-4 space-y-reverse sm:flex-row sm:space-y-0 sm:space-x-4">
        <!-- Cancel/Back Button -->
        <button
          type="button"
          @click="$emit('back')"
          data-testid="domain-add-cancel-btn"
          class="inline-flex w-full items-center justify-center rounded-md
            border border-gray-300
            bg-white px-4 py-2 text-base
            font-medium text-gray-700 shadow-sm
            hover:bg-gray-50
            focus:ring-2
            focus:ring-gray-500 focus:ring-offset-2 focus:outline-none sm:w-1/2
            dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200
            dark:hover:bg-gray-700 dark:focus:ring-offset-gray-900"
          :aria-label="t('web.layout.go_back_to_previous_page')">
          <svg
            class="mr-2 -ml-1 size-5"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18" />
          </svg>
          {{ t('web.COMMON.back') }}
        </button>

        <!-- Submit Button -->
        <button
          type="submit"
          :disabled="isSubmitting || needsChoice"
          data-testid="domain-add-submit"
          class="inline-flex w-full items-center justify-center rounded-md
            border border-transparent
            bg-brand-600 px-4 py-2 text-base
            font-medium text-white shadow-sm
            hover:bg-brand-700
            focus:ring-2
            focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed
            disabled:opacity-50 sm:w-1/2
            dark:bg-brand-500 dark:hover:bg-brand-400
            dark:focus:ring-offset-gray-900"
          aria-live="polite">
          <span
            v-if="isSubmitting"
            class="inline-flex items-center">
            <svg
              class="mr-2 -ml-1 size-5 animate-spin text-white motion-reduce:animate-none"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24">
              <circle
                class="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                stroke-width="4" />
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
            </svg>
            {{ t('web.COMMON.adding_ellipses') }}...
          </span>
          <span v-else>{{ continueLabel }}</span>
        </button>
      </div>
    </form>
  </div>
</template>
