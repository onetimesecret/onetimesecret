<script setup lang="ts">
import EmailObfuscator from '@/components/EmailObfuscator.vue';
import GithubCorner from '@/components/GithubCorner.vue';
import { WindowService } from '@/services/window.service';
import { setLanguage } from '@/i18n';
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
      await setLanguage(newLocale);
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
        Help Secure Communication Go Global
      </h2>

      <p class="mb-4">
        Since 2012, Onetime Secret has provided a secure way to share sensitive information worldwide. With
        users across regions where English isn't the primary language, accurate translations are essential
        for making secure communication accessible to everyone.
      </p>

      <p class="mb-4">
        Thanks to our community, we support over 20 languages today. However, with our rapid development
        pace, many translations need updates to stay current. This affects both onetimesecret.com and the
        thousands of self-hosted installations worldwide.
        <strong class="text-brand-500 dark:text-brand-400">Your language skills can help expand access to
          secure communication.</strong>
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
          Fork on GitHub and Submit a PR
        </a>
      </div>

      <hr class="my-8" />

      <h3 class="mb-4 text-2xl font-semibold">
        Translations
      </h3>
      <p class="mb-4">
        The following people have donated their time to help expand the reach of Onetime Secret:
      </p>

      <div
        v-for="translation in translations"
        :key="translation['code']">
        <h4 class="mb-2 text-xl font-semibold">
          {{ translation['name'] }}
          (<button
            @click="changeLocale(translation['code'])"
            class="inline-flex cursor-pointer items-center text-brand-500 hover:underline dark:text-brand-400"
            :aria-label="`Switch language to ${translation['name']}`"
            type="button">
            <span>switch</span>
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
        Ready to help? Some ways to contribute:
      </p>
      <ul class="mb-4 ml-6 list-disc">
        <li>Review existing translations using the language selector above</li>
        <li>Update a language directly through our GitHub project</li>
        <li>
          Start a new translation from our
          <a
            href="https://github.com/onetimesecret/onetimesecret/blob/develop/src/locales/en.json"
            class="text-brand-500 hover:underline dark:text-brand-400">English template</a>
        </li>
        <li>
          Send translations by email to
          <EmailObfuscator
            email="contribute@onetimesecret.com"
            subject="Translations"
          />
        </li>
      </ul>

      <p class="mb-4">
        Have questions? <router-link to="/feedback">
          Reach out to us
        </router-link> - remember to include your
        email if you're not logged in. Every translation helps more people communicate securely.
      </p>

      <p class="mb-4">
        - Delano
      </p>
    </article>
  </div>
</template>
