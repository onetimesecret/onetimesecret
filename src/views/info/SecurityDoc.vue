<script setup lang="ts">
import EmailObfuscator from '@/components/EmailObfuscator.vue';
</script>

<template>
  <article class="prose dark:prose-invert">
    <h2 class="mb-4 text-2xl font-bold dark:text-white">
      {{ $t('web.security.security-policy') }}
    </h2>
    <p class="mb-4 dark:text-gray-300">
      {{ $t('web.security.we-take-the-security-of-this-project-seriously-a') }}
    </p>
    <h3 class="mb-2 text-xl font-semibold dark:text-white">
      {{ $t('web.security.supported-versions') }}
    </h3>
    <p class="mb-4 dark:text-gray-300">
      {{ $t('web.security.we-provide-security-updates-for-the-following-ve') }}
    </p>
    <table class="mb-4 w-full">
      <thead>
        <tr class="bg-gray-100 dark:bg-gray-700">
          <th class="p-2 text-left dark:text-white">
            {{ $t('version') }}
          </th>
          <th class="p-2 text-left dark:text-white">
            {{ $t('supported') }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr class="border-b dark:border-gray-600">
          <td class="p-2 dark:text-gray-300">
            0.19.x+
          </td>
          <td class="p-2 dark:text-gray-300">
            {{ $t('emoji-checkmark') }}
          </td>
        </tr>
        <tr class="border-b dark:border-gray-600">
          <td class="p-2 dark:text-gray-300">
            0.18.x
          </td>
          <td class="p-2 dark:text-gray-300">
            {{ $t('emoji-checkmark') }}
          </td>
        </tr>
        <tr>
          <td class="p-2 dark:text-gray-300">
            &lt; 0.17.x
          </td>
          <td class="p-2 dark:text-gray-300">
            {{ $t('emoji-x') }}
          </td>
        </tr>
      </tbody>
    </table>
    <p class="mb-4 dark:text-gray-300">
      {{ $t('web.security.if-you-are-using-an-unsupported-version-we-stron') }}
    </p>
    <h3 class="mb-2 text-xl font-semibold dark:text-white">
      {{ $t('web.security.reporting-a-vulnerability') }}
    </h3>
    <p class="mb-4 dark:text-gray-300">
      {{ $t('web.security.if-you-discover-a-security-vulnerability-within-') }}
    </p>
    <h4 class="mb-2 text-lg font-semibold dark:text-white">
      {{ $t('web.security.how-to-report') }}
    </h4>
    <ol class="mb-4 list-decimal pl-6 dark:text-gray-300">
      <li class="mb-2">
        <strong>{{ $t('web.COMMON.field_email') }}</strong>{{ $t('web.security.send-an-email-to') }}
        <EmailObfuscator
          email="security@onetimesecret.com"
          subject="Vulnerability Report: [Brief Description]"
        />
        {{ $t('web.security.with-the-subject-line-vulnerability-report-brief') }}
      </li>
      <li>
        <strong>{{ $t('web.security.details') }}</strong>{{ $t('web.security.include-as-much-information-as-possible-about-th') }}
        <ul class="mt-2 list-disc pl-6">
          <li>{{ $t('web.security.a-detailed-description-of-the-vulnerability') }}</li>
          <li>{{ $t('web.security.steps-to-reproduce-the-issue') }}</li>
          <li>{{ $t('web.security.any-potential-impact') }}</li>
          <li>{{ $t('web.security.your-contact-information-for-follow-up-questions') }}</li>
        </ul>
      </li>
    </ol>
    <h4 class="mb-2 text-lg font-semibold dark:text-white">
      {{ $t('web.security.what-to-expect') }}
    </h4>
    <ol class="dark:text-gray-300">
      <li>
        <strong>{{ $t('web.security.acknowledgment') }}</strong>{{ $t('web.security.you-will-receive-an-acknowledgment-of-your-repor') }}
      </li>
      <li>
        <strong>{{ $t('web.security.initial-assessment') }}</strong>{{ $t('web.security.we-will-conduct-an-initial-assessment-of-the-vul') }}
      </li>
      <li>
        <strong>{{ $t('web.security.updates') }}</strong>{{ $t('web.security.you-can-expect-to-receive-updates-on-the-status-') }}
      </li>
    </ol>
    <h4 class="mb-2 text-lg font-semibold dark:text-white">
      {{ $t('web.security.resolution-process') }}
    </h4>
    <ol class="dark:text-gray-300">
      <li>
        <strong>{{ $t('web.security.accepted-vulnerabilities') }}</strong>{{ $t('web.security.if-the-vulnerability-is-accepted-we-will-work-on') }}
      </li>
      <li>
        <strong>{{ $t('web.security.declined-vulnerabilities') }}</strong>{{ $t('web.security.if-the-vulnerability-is-declined-we-will-provide') }}
      </li>
    </ol>
    <h4 class="mb-2 text-lg font-semibold dark:text-white">
      {{ $t('web.security.confidentiality') }}
    </h4>
    <p class="prose dark:text-gray-300">
      {{ $t('web.security.we-take-your-privacy-seriously-all-reports-will-') }}
    </p>
    <p class="prose dark:text-gray-300">
      {{ $t('web.security.thank-you-for-helping-us-keep-onetime-secret-sec') }}
    </p>
  </article>
</template>
