<script setup lang="ts">
import EmailObfuscator from '@/components/EmailObfuscator.vue';
import GithubCorner from '@/components/GithubCorner.vue';
import { WindowService } from '@/services/window.service';
import translations from '@/sources/translations.json';
import { useLanguageStore } from '@/stores/languageStore';

const languageStore = useLanguageStore();
const cust = WindowService.get('cust');

const changeLocale = async (newLocale: string) => {
  if (languageStore.getSupportedLocales.includes(newLocale)) {
    try {
      if (cust) {
        cust.locale = newLocale;
      }
      await languageStore.updateLanguage(newLocale);

    } catch (err) {
      console.error('Failed to update language:', err);
    }
  }
};
</script>

<template>
  <div>
    <GithubCorner />

    <article class="prose dark:prose-invert lg:prose-lg xl:prose-xl">
      <h2 class="mb-4 text-3xl font-bold text-brand-500 dark:text-brand-400">
        {{ $t('help-secure-communication-go-global') }}
      </h2>

      <p class="mb-4">
        {{ $t('since-2012-onetime-secret-has-provided-a-secure-') }}
      </p>

      <p class="mb-4">
        {{ $t('thanks-to-our-community-we-support-over-20-langu') }}
        <strong class="text-brand-500 dark:text-brand-400">{{ $t('your-language-skills-can-help-expand-access-to-s') }}</strong>
      </p>

      <div class="mt-8 text-center">
        <a
          href="https://github.com/onetimesecret/onetimesecret/fork"
          class="inline-flex items-center rounded bg-white px-4 py-2 font-brand text-2xl font-bold text-brand-500 hover:bg-brand-50 dark:bg-slate-800"
          target="_blank"
          rel="noopener noreferrer">
          <svg
            class="mr-2 size-4"
            fill="currentColor"
            viewBox="0 0 24 24"
            width="20"
            height="20"
            xmlns="http://www.w3.org/2000/svg">
            <path
              d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"
            />
          </svg>
          {{ $t('fork-on-github-and-submit-a-pr') }}
        </a>
      </div>

      <hr class="my-8" />

      <h3 class="mb-4 text-2xl font-semibold">
        {{ $t('translations') }}
      </h3>
      <p class="mb-4">
        {{ $t('the-following-people-have-donated-their-time-to-') }}
      </p>

      <div
        v-for="translation in translations"
        :key="translation['code']">
        <h4 class="mb-2 text-xl font-semibold">
          {{ translation['name'] }}
          (<button
            @click="changeLocale(translation['code'])"
            class="inline-flex cursor-pointer items-center text-brand-500 hover:underline dark:text-brand-400"
            :aria-label="translation['name']"
            type="button">
            <span>{{ $t('switch') }}</span>
          </button>)
        </h4>
        <ul class="mb-4 list-disc pl-5">
          <li
            v-for="(translator, index) in translation['translators']"
            :key="`${translation['code']}-${index}}`">
            <a
              v-if="translator['url']"
              :href="translator['url']"
              target="_blank"
              rel="noopener noreferrer"
              class="text-brand-500 hover:underline dark:text-brand-400">
              {{ translator['name'] }}
            </a>
            <span v-else>{{ translator['name'] }}</span>
            ({{ translator['date'] }})
          </li>
        </ul>
      </div>

      <hr class="my-8" />

      <p class="mb-4">
        {{ $t('ready-to-help-some-ways-to-contribute') }}
      </p>
      <ul class="mb-4 ml-6 list-disc">
        <li>{{ $t('review-existing-translations-using-the-language-') }}</li>
        <li>{{ $t('update-a-language-directly-through-our-github-pr') }}</li>
        <li>
          {{ $t('start-a-new-translation-from-our') }}
          <a
            href="https://github.com/onetimesecret/onetimesecret/blob/develop/src/locales/en.json"
            class="text-brand-500 hover:underline dark:text-brand-400">{{ $t('english-template') }}</a>
        </li>
        <li>
          {{ $t('send-translations-by-email-to') }}
          <EmailObfuscator
            email="contribute@onetimesecret.com"
            subject="Translations"
          />
        </li>
      </ul>

      <p class="mb-4">
        {{ $t('have-questions') }} <router-link to="/feedback">
          {{ $t('reach-out-to-us') }}
        </router-link> {{ $t('remember-to-include-your-email-if-youre-not-logg') }}
      </p>

      <p class="mb-4">
        - {{ $t('delano') }}
      </p>
    </article>
  </div>
</template>
