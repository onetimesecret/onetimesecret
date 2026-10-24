<!-- src/shared/components/ui/LocaleLoadNotice.vue -->

<script setup lang="ts">
  import { toLanguageTag } from '@/i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useLanguageStore } from '@/shared/stores/languageStore';
  import { localeCodes } from '@/sources/languages';
  import { storeToRefs } from 'pinia';
  import { computed, ref } from 'vue';
  import { I18nT, useI18n } from 'vue-i18n';

  /**
   * The notice for a language whose messages did not load (the language
   * store's localeLoadFailure). It names that language and the one shown
   * instead, says the visitor can carry on in it, and points to the feedback
   * form in case the failure repeats.
   *
   * Inline and persistent, not a toast: after a failed start the visitor never
   * saw the language they asked for, and nothing else on the page says why. It
   * stays until dismissed or until a later activation succeeds (the store
   * clears it then). If messages loaded but the preference could not be saved,
   * it offers retry and dismiss instead. A load failure takes priority when
   * both failures exist.
   *
   * Its own text is in the active locale, i.e. the one shown. Mounted in
   * App.vue above the layout so it appears on every route of both bundles,
   * like StaleSessionNotice. The feedback link is a plain href: /feedback is a
   * customer route, and the colonel bundle's router has no route for it.
   */

  interface LanguageLabel {
    /** BCP 47 tag for the name's `lang` attribute. */
    tag: string;
    /** Native name, as the language toggle lists it; the code when unknown. */
    name: string;
  }

  const { t } = useI18n();
  const languageStore = useLanguageStore();
  const { localeLoadFailure, localeSaveFailure } = storeToRefs(languageStore);
  const retrying = ref(false);

  const label = (locale: string): LanguageLabel => ({
    tag: toLanguageTag(locale),
    name: Object.hasOwn(localeCodes, locale)
      ? localeCodes[locale as keyof typeof localeCodes]
      : locale,
  });

  const notice = computed(() => {
    const failure = localeLoadFailure.value;
    return failure && { requested: label(failure.requested), shown: label(failure.shown) };
  });

  const dismiss = () => languageStore.dismissLocaleLoadFailure();

  const retrySave = async () => {
    if (retrying.value) return;

    retrying.value = true;
    try {
      await languageStore.retryLanguageSave();
    } finally {
      retrying.value = false;
    }
  };
</script>

<template>
  <div
    v-if="notice"
    role="alert"
    data-testid="locale-load-notice"
    :class="[
      'border-b-2 border-amber-500 bg-amber-100 px-4 py-2 text-amber-900',
      'dark:border-amber-400 dark:bg-amber-950 dark:text-amber-100',
    ]">
    <div class="container mx-auto flex items-start justify-between gap-4">
      <div class="flex min-w-0 items-start gap-3">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="mt-0.5 size-5 shrink-0 text-amber-700 dark:text-amber-300"
          aria-hidden="true" />
        <div class="min-w-0 text-sm">
          <I18nT
            keypath="web.layout.locale_load_failed.title"
            tag="p"
            class="font-semibold"
            scope="global">
            <template #requested>
              <span :lang="notice.requested.tag">{{ notice.requested.name }}</span>
            </template>
          </I18nT>
          <I18nT
            keypath="web.layout.locale_load_failed.body"
            tag="p"
            scope="global">
            <template #shown>
              <span :lang="notice.shown.tag">{{ notice.shown.name }}</span>
            </template>
            <template #feedback>
              <a
                href="/feedback"
                data-testid="locale-load-notice-feedback"
                :class="[
                  'font-semibold underline hover:text-amber-700 dark:hover:text-amber-300',
                  'focus:ring-2 focus:ring-amber-600 focus:outline-none dark:focus:ring-amber-300',
                ]">
                {{ t('web.layout.locale_load_failed.feedback_link') }}
              </a>
            </template>
          </I18nT>
        </div>
      </div>

      <button
        type="button"
        data-testid="locale-load-notice-dismiss"
        :aria-label="t('web.layout.locale_load_failed.dismiss')"
        :class="[
          'shrink-0 rounded-md p-1 text-amber-800 transition-colors hover:bg-amber-200',
          'focus:ring-2 focus:ring-amber-600 focus:outline-none',
          'dark:text-amber-200 dark:hover:bg-amber-900/60 dark:focus:ring-amber-300',
        ]"
        @click="dismiss">
        <OIcon
          collection="heroicons"
          name="x-mark"
          class="size-5"
          aria-hidden="true" />
      </button>
    </div>
  </div>
  <div
    v-else-if="localeSaveFailure"
    role="alert"
    data-testid="locale-save-notice"
    :class="[
      'border-b-2 border-amber-500 bg-amber-100 px-4 py-2 text-amber-900',
      'dark:border-amber-400 dark:bg-amber-950 dark:text-amber-100',
    ]">
    <div class="container mx-auto flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
      <div class="flex min-w-0 items-start gap-3">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="mt-0.5 size-5 shrink-0 text-amber-700 dark:text-amber-300"
          aria-hidden="true" />
        <div class="min-w-0 text-sm">
          <p class="font-semibold">
            {{ t('web.layout.locale_save_failed.title') }}
          </p>
          <p>{{ t('web.layout.locale_save_failed.body') }}</p>
        </div>
      </div>

      <div class="flex shrink-0 items-center gap-2">
        <button
          type="button"
          data-testid="locale-save-notice-retry"
          :disabled="retrying"
          :aria-busy="retrying"
          :class="[
            'inline-flex items-center gap-2 rounded-md border border-amber-700 px-3 py-1 text-sm font-semibold',
            'text-amber-900 transition-colors hover:bg-amber-200',
            'focus:ring-2 focus:ring-amber-600 focus:ring-offset-1 focus:outline-none',
            'disabled:cursor-wait disabled:opacity-60',
            'dark:border-amber-300 dark:text-amber-100 dark:hover:bg-amber-900/60 dark:focus:ring-amber-300',
          ]"
          @click="retrySave">
          <OIcon
            v-if="retrying"
            collection="heroicons"
            name="arrow-path"
            class="size-4 animate-spin motion-reduce:animate-none"
            aria-hidden="true" />
          {{ t('web.layout.locale_save_failed.retry') }}
        </button>
        <button
          type="button"
          data-testid="locale-save-notice-dismiss"
          :aria-label="t('web.layout.locale_save_failed.dismiss')"
          :class="[
            'rounded-md p-1 text-amber-800 transition-colors hover:bg-amber-200',
            'focus:ring-2 focus:ring-amber-600 focus:outline-none',
            'dark:text-amber-200 dark:hover:bg-amber-900/60 dark:focus:ring-amber-300',
          ]"
          @click="languageStore.dismissLocaleSaveFailure()">
          <OIcon
            collection="heroicons"
            name="x-mark"
            class="size-5"
            aria-hidden="true" />
        </button>
      </div>
    </div>
  </div>
</template>
