// src/views/About.vue

<script setup lang="ts">

import { WindowService } from '@/services/window.service';
import { Plan } from '@/schemas/models';
import { ref, computed } from 'vue';
import { onMounted } from 'vue';

const { available_plans, default_planid } = WindowService.getMultiple({
  available_plans: null,
  default_planid: 'basic',
});
const defaultPlan = ref({} as Plan);
const anonymousPlan = ref({} as Plan);

const secondsToDays = (seconds: number) => {
  return seconds != null ? Math.floor(seconds / 86400) : 0;
};

const bytesToKB = (bytes: number) => {
  return bytes != null ? Math.round(bytes / 1024) : 0;
};

// Anonymous users can create secrets that last up to {{ anonymousTtlDays }} days
// and have a maximum size of {{ anonymousSizeKB }} KB. Free account holders get
// extended benefits: secrets can last up to {{ defaultTtlDays }} days and can be
// up to {{ defaultSizeKB }} KB in size. Account holders also get access to
// additional features like burn-before-reading options, which allow senders to
// delete secrets before they're received.
// TODO: Cleanup this mess of plans
const anonymousTtlDays = computed(() => secondsToDays(anonymousPlan?.value?.options?.ttl ?? (3600*24*7)));
const anonymousSizeKB = computed(() => bytesToKB(anonymousPlan?.value?.options?.size ?? 102400));
const defaultTtlDays = computed(() => secondsToDays(defaultPlan?.value?.options?.ttl ?? (3600*24*14)));
const defaultSizeKB = computed(() => bytesToKB(defaultPlan?.value?.options?.size ?? 1024000));

onMounted(() => {
  if (available_plans && default_planid) {
    defaultPlan.value = available_plans[default_planid] ?? null;
    anonymousPlan.value = available_plans?.anonymous;
  }
});
const githubLink = '<a href="https://github.com/onetimesecret/onetimesecret">our code remains open-source</a>';
const privacyPolicyLink = `<router-link to="/info/privacy">privacy policy</router-link>`;
</script>

<template>
  <article class="prose dark:prose-invert md:prose-lg lg:prose-xl">
    <h2 class="intro">
      {{ $t('about.title') }}
    </h2>

    <p class="">
      {{ $t('about.intro.paragraph1', { name: 'Delano' }) }}
    </p>

    <p>
      {{ $t('about.intro.paragraph2') }}
    </p>

    <p v-html="$t('about.intro.paragraph3', { githubLink })"></p>

    <p>
      {{ $t('about.intro.paragraph4') }}
    </p>

    <p class="">
      {{ $t('about.intro.feedback_hint') }}
    </p>

    <p class="">
      {{ $t('about.intro.signature', { name: 'Delano' }) }}
    </p>

    <p style="margin-left: 40%; margin-right: 40%">
      <a
        href="https://delanotes.com/"
        title="Delano Mandelbaum"><img
          src="@/assets/img/delano-g.png"
          width="95"
          height="120"
          border="0"
        /></a>
    </p>

    <h3>F.A.Q.</h3>

    <h4>{{ $t('about.faq.why_use_title') }}</h4>
    <p>
      {{ $t('about.faq.why_use_description') }}
    </p>

    <h4>{{ $t('about.faq.file_limitation_title') }}</h4>
    <p>
      {{ $t('about.faq.file_limitation_description') }}
    </p>

    <h4>{{ $t('about.faq.text_copy_title') }}</h4>
    <p>
      {{ $t('about.faq.text_copy_description') }}
    </p>

    <h4>{{ $t('about.faq.secret_retrieval_title') }}</h4>
    <p>{{ $t('about.faq.secret_retrieval_description') }}</p>

    <span v-if="anonymousPlan && defaultPlan">
      <h4>{{ $t('about.faq.account_difference_title') }}</h4>
      <p>
        {{ $t('about.faq.account_difference_description', {
          anonymousTtlDays,
          anonymousSizeKB,
          defaultTtlDays,
          defaultSizeKB
        }) }}
      </p>
    </span>

    <h4>{{ $t('about.faq.law_enforcement_title') }}</h4>
    <p v-html="$t('about.intro.paragraph3', { githubLink })"></p>
    <p v-html="$t('about.faq.law_enforcement_description', { privacyPolicyLink: privacyPolicyLink })"></p>

    <h4>{{ $t('about.faq.trust_title') }}</h4>
    <p>
      {{ $t('about.faq.trust_description') }}
    </p>
    <ul>
      <li>{{ $t('about.faq.trust_points.0') }}</li>
      <li>{{ $t('about.faq.trust_points.1') }}</li>
      <li>{{ $t('about.faq.trust_points.2') }}</li>
      <li>{{ $t('about.faq.trust_points.3') }}</li>
    </ul>

    <h4>{{ $t('about.faq.passphrase_title') }}</h4>
    <p>
      {{ $t('about.faq.passphrase_description') }}
    </p>
    <ul>
      <li>{{ $t('about.faq.passphrase_points.0') }}</li>
      <li>{{ $t('about.faq.passphrase_points.1') }}</li>
      <li>{{ $t('about.faq.passphrase_points.2') }}</li>
      <li>{{ $t('about.faq.passphrase_points.3') }}</li>
    </ul>
    <p>
      {{ $t('about.faq.passphrase_final_note') }}
    </p>
  </article>
</template>
