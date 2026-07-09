<!-- src/apps/workspace/components/domains/DomainForm.vue -->

<script setup lang="ts">
  import DomainInput from '@/apps/workspace/components/domains/DomainInput.vue';
  import { addDomainRequestSchema } from '@/schemas/api/domains/requests';
  import { analyzeDomain } from '@/utils/parse/domain';
  import { ref, computed, onBeforeUnmount } from 'vue';
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

  // What the user is typing right now (bound to the input, updates instantly).
  const raw = ref('');
  // A settled copy of `raw` that drives the echo/apex guidance. We wait for a
  // short pause in typing before reflecting a new value so the form doesn't
  // reflow on every keystroke — instant option-churn mid-word reads as twitchy;
  // a beat of stillness before revealing the choices feels considered.
  const settled = ref('');
  const REVEAL_DELAY_MS = 350;
  let revealTimer: ReturnType<typeof setTimeout> | null = null;

  const choice = ref<Choice>(null);
  // Gates every inline error: nothing complains until the user tries to submit.
  const attempted = ref(false);

  // Guidance always reads from the settled value, never the raw keystrokes.
  const analysis = computed(() => analyzeDomain(settled.value));

  const clearRevealTimer = () => {
    if (revealTimer) {
      clearTimeout(revealTimer);
      revealTimer = null;
    }
  };

  // Any keystroke invalidates the current guidance: drop the pending choice and
  // reset the attempted flag so stale errors clear immediately.
  const onInput = (value: string) => {
    raw.value = value;
    choice.value = null;
    attempted.value = false;

    clearRevealTimer();
    if (value.trim() === '') {
      // Clearing the field hides the options at once — no lingering cards.
      settled.value = '';
      return;
    }
    // Otherwise let typing settle before we reveal (or change) the options.
    revealTimer = setTimeout(() => {
      settled.value = value;
      revealTimer = null;
    }, REVEAL_DELAY_MS);
  };

  onBeforeUnmount(clearRevealTimer);

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
    // Submitting resolves the pending reveal immediately: act on exactly what's
    // typed, not a value still waiting out the settle delay.
    clearRevealTimer();
    settled.value = raw.value.trim() === '' ? '' : raw.value;
    attempted.value = true;

    const a = analysis.value;
    // Empty and invalid both surface an inline error and stop here.
    if (a.empty || !a.valid) return;
    // Apex with no address chosen yet — reveal the cards rather than submit.
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
  <div class="space-y-8">
    <form
      @submit.prevent="handleSubmit"
      data-testid="domain-add-form"
      class="space-y-6">
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

      <!-- Echo: confirm a deeper hostname we will use verbatim. Revealed with a
           gentle fade once typing settles, rather than snapping in per keystroke. -->
      <Transition
        enter-active-class="transition duration-300 ease-out motion-reduce:transition-none"
        enter-from-class="opacity-0 translate-y-1"
        enter-to-class="opacity-100 translate-y-0">
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
      </Transition>

      <!-- Apex chooser: pick where secret links live on a bare registrable.
           Grouped and revealed with a gentle fade once typing settles. -->
      <Transition
        enter-active-class="transition duration-300 ease-out motion-reduce:transition-none"
        enter-from-class="opacity-0 translate-y-1"
        enter-to-class="opacity-100 translate-y-0">
        <fieldset
          v-if="showCards"
          data-testid="domain-apex-cards"
          class="space-y-4">
          <legend class="text-sm font-medium text-gray-900 dark:text-white">
            {{ t('web.domains.add.apex_question') }}
          </legend>
          <p class="text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.domains.add.no_wrong_answer') }}
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
            class="space-y-5">
            <!-- Popular subdomains: the low-consequence, recommended path -->
            <div class="space-y-2">
              <p class="text-xs font-semibold tracking-wide text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.domains.add.subdomains_label') }}
              </p>
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
            </div>

            <!-- Or use your whole domain: higher-consequence, amber caution -->
            <div class="space-y-2">
              <p class="text-xs font-semibold tracking-wide text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.domains.add.root_group_label') }}
              </p>
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
          </div>
        </fieldset>
      </Transition>

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
