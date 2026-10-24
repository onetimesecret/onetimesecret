<!-- src/apps/workspace/components/domains/DomainSsoMetadataImport.vue -->

<script setup lang="ts">
  /**
   * SAML IdP metadata import, shown above the IdP trio in DomainSsoConfigForm.
   *
   * Presentational, like the form: the preview, the fetch input and the
   * actions live in useSsoConfig (docs/specs/sso/saml-idp-metadata-consumption.md,
   * Phase 1). A fetch fills a PREVIEW, never the form; "Apply metadata"
   * copies a complete preview into the form as one update, and only the
   * form's own save persists it. The fetch is a secondary action: the
   * form's primary action stays "Save and check".
   */
  import type {
    IdpMetadataCertificate,
    IdpMetadataProblem,
    SsoMetadataFetchErrorCode,
    SsoMetadataProblemCode,
  } from '@/schemas/api/domains/responses/sso-config';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import type {
    SsoConfigFormState,
    SsoMetadataFetchFailure,
    SsoMetadataPreview,
  } from '@/shared/composables/useSsoConfig';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  const props = defineProps<{
    /** The fetch input (useSsoConfig metadataFetchUrl), not the saved source. */
    metadataFetchUrl: string;
    preview: SsoMetadataPreview | null;
    isFetching: boolean;
    failure: SsoMetadataFetchFailure | null;
    /** useSsoConfig canApplyMetadata: the one gate on "Apply metadata". */
    canApply: boolean;
    /** Read only: its idp_metadata_url is the source the trio was imported from. */
    formState: SsoConfigFormState;
    /** The stored source could not be revealed (unreadable_fields). */
    sourceUnreadable: boolean;
  }>();

  const emit = defineEmits<{
    (e: 'update:metadataFetchUrl', value: string): void;
    (e: 'fetch'): void;
    (e: 'select-certificate', index: number): void;
    (e: 'apply'): void;
    /** Clear formState.idp_metadata_url; the trio stays as it is. */
    (e: 'clear-source'): void;
  }>();

  const { t } = useI18n();

  /**
   * Messages per fetch error_code and per problem code, keyed per contract
   * value so a code added to the contract fails type-check here until it has
   * one. A code this client does not know shows the server's message.
   */
  const FETCH_ERROR_KEYS: Record<SsoMetadataFetchErrorCode, string> = {
    invalid_metadata_url: 'web.organizations.sso.metadata_error_invalid_metadata_url',
    blocked_target: 'web.organizations.sso.metadata_error_blocked_target',
    timeout: 'web.organizations.sso.metadata_error_timeout',
    ssl_error: 'web.organizations.sso.metadata_error_ssl_error',
    connection_failed: 'web.organizations.sso.metadata_error_connection_failed',
    http_error: 'web.organizations.sso.metadata_error_http_error',
    metadata_not_found: 'web.organizations.sso.metadata_error_metadata_not_found',
    metadata_too_large: 'web.organizations.sso.metadata_error_metadata_too_large',
    invalid_metadata: 'web.organizations.sso.metadata_error_invalid_metadata',
    aggregate_metadata: 'web.organizations.sso.metadata_error_aggregate_metadata',
    unreadable_certificate: 'web.organizations.sso.metadata_error_unreadable_certificate',
    unexpected_error: 'web.organizations.sso.metadata_error_unexpected_error',
  };

  const PROBLEM_KEYS: Record<SsoMetadataProblemCode, string> = {
    invalid_entity_id: 'web.organizations.sso.metadata_problem_invalid_entity_id',
    invalid_sso_url: 'web.organizations.sso.metadata_problem_invalid_sso_url',
    no_sso_url: 'web.organizations.sso.metadata_problem_no_sso_url',
    unsupported_sso_binding: 'web.organizations.sso.metadata_problem_unsupported_sso_binding',
    no_signing_certificates: 'web.organizations.sso.metadata_problem_no_signing_certificates',
    no_usable_signing_certificates:
      'web.organizations.sso.metadata_problem_no_usable_signing_certificates',
    unreadable_signing_certificates:
      'web.organizations.sso.metadata_problem_unreadable_signing_certificates',
    tenant_level_entra_metadata:
      'web.organizations.sso.metadata_problem_tenant_level_entra_metadata',
  };

  /** Own keys only: a wire code such as "constructor" must not hit the prototype. */
  function messageKey<K extends string>(map: Record<K, string>, code: string | null) {
    if (code === null || !Object.prototype.hasOwnProperty.call(map, code)) return null;
    return map[code as K];
  }

  const canFetch = computed(() => props.metadataFetchUrl.trim() !== '' && !props.isFetching);

  const handleFetch = () => {
    if (canFetch.value) emit('fetch');
  };

  const failureText = computed(() => {
    const failure = props.failure;
    if (!failure) return '';
    const key = messageKey(FETCH_ERROR_KEYS, failure.errorCode);
    return key ? t(key) : failure.message;
  });

  /** The server's message is passed as {reason} for the codes that use it. */
  const problemText = (problem: IdpMetadataProblem): string => {
    const key = messageKey(PROBLEM_KEYS, problem.code);
    return key ? t(key, { reason: problem.message }) : problem.message;
  };

  const response = computed(() => props.preview?.response ?? null);

  const blockingProblems = computed(
    () => response.value?.problems.filter((problem) => problem.severity === 'blocking') ?? []
  );

  const advisories = computed(
    () => response.value?.problems.filter((problem) => problem.severity === 'advisory') ?? []
  );

  const certificates = computed(() => response.value?.signing_certificates ?? []);

  /** A picker only when there is a choice; one certificate is shown as is. */
  const hasCertificateChoice = computed(() => certificates.value.length > 1);

  const selectedIndex = computed(() => props.preview?.selectedCertIndex ?? null);

  /**
   * The certificate with the latest not_before, labelled "newest" when there
   * are several and exactly one holds that date. A label only: Entra lists an
   * added certificate before it is activated, so the newest one is not
   * necessarily the one signing, and it is never selected for the admin.
   */
  const newestIndex = computed(() => {
    if (!hasCertificateChoice.value) return null;
    const starts = certificates.value.map((cert) => Date.parse(cert.not_before));
    const latest = Math.max(...starts.filter((start) => Number.isFinite(start)));
    if (!Number.isFinite(latest)) return null;
    const holders = starts.flatMap((start, index) => (start === latest ? [index] : []));
    return holders.length === 1 ? holders[0] : null;
  });

  const formatDate = (raw: string): string => {
    const date = new Date(raw);
    return Number.isNaN(date.getTime()) ? raw : date.toLocaleDateString();
  };

  const validityText = (cert: IdpMetadataCertificate) =>
    t('web.organizations.sso.metadata_cert_validity', {
      from: formatDate(cert.not_before),
      until: formatDate(cert.not_after),
    });

  const selectCertificate = (index: number) => {
    if (certificates.value[index]?.problem === null) emit('select-certificate', index);
  };

  /**
   * Nothing blocks the import except the missing choice: say so next to the
   * disabled Apply button rather than leave it unexplained.
   */
  const selectionPending = computed(
    () =>
      !!response.value &&
      blockingProblems.value.length === 0 &&
      selectedIndex.value === null &&
      certificates.value.some((cert) => cert.problem === null)
  );

  /** The form already holds exactly this preview's values. */
  const applied = computed(() => {
    const preview = props.preview;
    if (!preview || !props.canApply || preview.selectedCertIndex === null) return false;
    const cert = preview.response.signing_certificates[preview.selectedCertIndex];
    const form = props.formState;
    return (
      form.idp_entity_id === preview.response.idp_entity_id &&
      form.idp_sso_service_url === preview.response.idp_sso_service_url &&
      form.idp_cert === cert?.pem &&
      form.idp_metadata_url === preview.metadataUrl
    );
  });

  const sourceUrl = computed(() => props.formState.idp_metadata_url.trim());
</script>

<template>
  <div
    data-testid="sso-saml-metadata"
    class="space-y-4">
    <!-- Fetch input: a secondary action. Enter fetches rather than submitting
         the surrounding form (which would save or run the check). type=text
         (inputmode=url) so a half-typed URL here never trips the browser's
         validation of that form: this value is not saved. -->
    <div>
      <label
        for="domain-sso-idp-metadata-url"
        class="block text-sm font-medium text-gray-700 dark:text-gray-300">
        {{ t('web.organizations.sso.metadata_url') }}
      </label>
      <p
        id="domain-sso-idp-metadata-url-hint"
        class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.organizations.sso.metadata_url_hint') }}
      </p>
      <div class="mt-2 flex flex-col gap-2 sm:flex-row">
        <input
          id="domain-sso-idp-metadata-url"
          data-testid="sso-metadata-url-input"
          :value="metadataFetchUrl"
          @input="emit('update:metadataFetchUrl', ($event.target as HTMLInputElement).value)"
          @keydown.enter.prevent="handleFetch"
          type="text"
          inputmode="url"
          autocomplete="off"
          spellcheck="false"
          :placeholder="t('web.organizations.sso.metadata_url_placeholder')"
          aria-describedby="domain-sso-idp-metadata-url-hint"
          class="block w-full min-w-0 flex-1 rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400" />
        <button
          type="button"
          data-testid="sso-metadata-fetch"
          @click="handleFetch"
          :disabled="!canFetch"
          :aria-busy="isFetching"
          class="inline-flex shrink-0 items-center justify-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-600 dark:text-gray-100 dark:ring-gray-500 dark:hover:bg-gray-500">
          <OIcon
            v-if="isFetching"
            collection="heroicons"
            name="arrow-path"
            size="4"
            class="animate-spin motion-reduce:animate-none"
            aria-hidden="true" />
          <OIcon
            v-else
            collection="heroicons"
            name="arrow-down-tray"
            size="4"
            aria-hidden="true" />
          {{
            isFetching
              ? t('web.organizations.sso.metadata_fetching')
              : t('web.organizations.sso.metadata_fetch_button')
          }}
        </button>
      </div>
    </div>

    <!-- Where the trio in the form came from: formState.idp_metadata_url,
         saved with the record. Only applying a preview sets it; a failed or
         blocked fetch never does. Clearing it leaves the trio alone. -->
    <div
      v-if="sourceUrl || sourceUnreadable"
      data-testid="sso-metadata-source"
      class="rounded-md bg-gray-50 px-3 py-2 dark:bg-gray-900/40">
      <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
        <span
          id="domain-sso-idp-metadata-source-label"
          class="text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.organizations.sso.metadata_source') }}
        </span>
        <code
          v-if="sourceUrl"
          data-testid="sso-metadata-source-url"
          aria-labelledby="domain-sso-idp-metadata-source-label"
          class="min-w-0 flex-1 font-mono text-xs break-all text-gray-800 dark:text-gray-200">
          {{ sourceUrl }}
        </code>
        <button
          v-if="sourceUrl"
          type="button"
          data-testid="sso-metadata-source-clear"
          :aria-label="t('web.organizations.sso.metadata_source_clear_label')"
          @click="emit('clear-source')"
          class="inline-flex shrink-0 items-center gap-1 rounded-md px-2 py-1 text-sm font-medium text-gray-500 hover:bg-gray-100 hover:text-gray-900 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white">
          <OIcon
            collection="heroicons"
            name="x-mark"
            class="size-4"
            aria-hidden="true" />
          {{ t('web.organizations.sso.metadata_source_clear') }}
        </button>
      </div>
      <p
        v-if="!sourceUrl"
        data-testid="sso-metadata-source-unreadable"
        class="mt-1 text-sm text-red-600 dark:text-red-400">
        {{ t('web.organizations.sso.metadata_source_unreadable') }}
      </p>
      <p
        v-else
        class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        {{ t('web.organizations.sso.metadata_source_hint') }}
      </p>
    </div>

    <p
      v-if="isFetching"
      data-testid="sso-metadata-fetching"
      role="status"
      class="text-sm text-gray-500 dark:text-gray-400">
      {{ t('web.organizations.sso.metadata_fetching') }}
    </p>

    <!-- No preview: the fetch failed or was refused. Announced like the
         Test Connection failure. -->
    <div
      v-else-if="failure"
      data-testid="sso-metadata-error"
      :data-error-code="failure.errorCode ?? undefined"
      role="alert"
      aria-live="assertive"
      class="rounded-md bg-red-50 p-4 dark:bg-red-900/20">
      <div class="flex">
        <OIcon
          collection="heroicons"
          name="x-circle-solid"
          class="size-5 shrink-0 text-red-400"
          aria-hidden="true" />
        <div class="ml-3 min-w-0">
          <p class="text-sm font-medium text-red-800 dark:text-red-200">
            {{ failureText }}
          </p>
          <dl
            v-if="failure.errorCode || failure.httpStatus"
            class="mt-2 space-y-1 text-sm text-red-700 dark:text-red-300">
            <div
              v-if="failure.errorCode"
              class="flex gap-2">
              <dt class="font-medium">{{ t('web.COMMON.error_code') }}:</dt>
              <dd class="font-mono break-all">
                {{ failure.errorCode }}
              </dd>
            </div>
            <div
              v-if="failure.httpStatus"
              class="flex gap-2">
              <dt class="font-medium">{{ t('web.COMMON.http_status') }}:</dt>
              <dd>{{ failure.httpStatus }}</dd>
            </div>
          </dl>
        </div>
      </div>
    </div>

    <!-- The preview. Nothing here writes the form until Apply. -->
    <section
      v-else-if="preview && response"
      data-testid="sso-metadata-preview"
      aria-labelledby="sso-metadata-preview-title"
      class="space-y-4 rounded-md border border-gray-200 p-4 dark:border-gray-700">
      <div>
        <h4
          id="sso-metadata-preview-title"
          class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.organizations.sso.metadata_preview_title') }}
        </h4>
        <p
          role="status"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.metadata_preview_hint') }}
        </p>
      </div>

      <dl class="space-y-2 text-sm">
        <div class="sm:flex sm:gap-4">
          <dt class="font-medium text-gray-700 sm:w-44 sm:shrink-0 dark:text-gray-300">
            {{ t('web.organizations.sso.idp_entity_id') }}
          </dt>
          <dd
            data-testid="sso-metadata-entity-id"
            class="mt-0.5 min-w-0 flex-1 font-mono text-xs break-all text-gray-900 sm:mt-0 dark:text-gray-100">
            {{ response.idp_entity_id ?? t('web.organizations.sso.metadata_value_missing') }}
          </dd>
        </div>
        <div class="sm:flex sm:gap-4">
          <dt class="font-medium text-gray-700 sm:w-44 sm:shrink-0 dark:text-gray-300">
            {{ t('web.organizations.sso.idp_sso_service_url') }}
          </dt>
          <dd
            data-testid="sso-metadata-sso-url"
            class="mt-0.5 min-w-0 flex-1 font-mono text-xs break-all text-gray-900 sm:mt-0 dark:text-gray-100">
            {{ response.idp_sso_service_url ?? t('web.organizations.sso.metadata_value_missing') }}
          </dd>
        </div>
      </dl>

      <!-- Blocking problems are import errors: Apply stays disabled. -->
      <div
        v-if="blockingProblems.length > 0"
        data-testid="sso-metadata-blocking"
        role="alert"
        class="rounded-md bg-red-50 px-3 py-2 dark:bg-red-900/20">
        <p class="text-sm font-medium text-red-800 dark:text-red-200">
          {{ t('web.organizations.sso.metadata_blocking_title') }}
        </p>
        <ul class="mt-1 list-disc space-y-1 pl-5 text-sm text-red-700 dark:text-red-300">
          <li
            v-for="(problem, index) in blockingProblems"
            :key="`${index}-${problem.code}`"
            data-testid="sso-metadata-problem"
            :data-code="problem.code">
            {{ problemText(problem) }}
          </li>
        </ul>
      </div>

      <!-- Advisories are warnings: they never block an otherwise complete
           import. Amber is the fixed warning hue (#4132); the text carries
           the meaning on its own (WCAG 1.4.1). -->
      <div
        v-if="advisories.length > 0"
        data-testid="sso-metadata-advisories"
        role="status"
        class="flex items-start gap-2 rounded-md bg-amber-50 px-3 py-2 dark:bg-amber-900/20">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400"
          aria-hidden="true" />
        <ul class="space-y-1 text-sm text-amber-700 dark:text-amber-300">
          <li
            v-for="(problem, index) in advisories"
            :key="`${index}-${problem.code}`"
            data-testid="sso-metadata-advisory"
            :data-code="problem.code">
            {{ problemText(problem) }}
          </li>
        </ul>
      </div>

      <!-- Signing certificates (signing use only). Two or more: a radio
           group with nothing preselected; the SHA-1 thumbprint is what the
           Entra portal shows for the certificate it marks Active. One: shown
           without a picker. A certificate the save would refuse carries the
           server's reason and cannot be chosen. -->
      <div
        v-if="certificates.length > 0"
        data-testid="sso-metadata-certificates">
        <p
          id="sso-metadata-certificates-title"
          class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.organizations.sso.metadata_certificates') }}
        </p>
        <p
          v-if="hasCertificateChoice"
          id="sso-metadata-certificates-hint"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.metadata_certificates_choose_hint') }}
        </p>
        <div
          :role="hasCertificateChoice ? 'radiogroup' : undefined"
          :aria-labelledby="hasCertificateChoice ? 'sso-metadata-certificates-title' : undefined"
          :aria-describedby="hasCertificateChoice ? 'sso-metadata-certificates-hint' : undefined"
          class="mt-2 space-y-2">
          <component
            :is="hasCertificateChoice ? 'label' : 'div'"
            v-for="(cert, index) in certificates"
            :key="`${index}-${cert.fingerprint_sha256}`"
            :data-testid="`sso-metadata-cert-${index}`"
            :data-selected="selectedIndex === index ? 'true' : 'false'"
            :class="[
              'flex items-start gap-3 rounded-lg border p-3 transition-colors',
              cert.problem !== null
                ? 'border-gray-200 opacity-60 dark:border-gray-700'
                : selectedIndex === index
                  ? 'border-brand-500 bg-brand-50/50 dark:border-brand-400 dark:bg-brand-900/10'
                  : 'border-gray-200 dark:border-gray-700',
              hasCertificateChoice && cert.problem !== null ? 'cursor-not-allowed' : '',
              hasCertificateChoice && cert.problem === null
                ? 'cursor-pointer focus-within:ring-2 focus-within:ring-brand-500 hover:border-gray-300 hover:bg-gray-50 dark:hover:border-gray-600 dark:hover:bg-gray-700/30'
                : '',
            ]">
            <input
              v-if="hasCertificateChoice"
              type="radio"
              name="sso-metadata-certificate"
              :value="index"
              :checked="selectedIndex === index"
              :disabled="cert.problem !== null"
              :aria-labelledby="`sso-metadata-cert-${index}-subject`"
              :aria-describedby="`sso-metadata-cert-${index}-details`"
              @change="selectCertificate(index)"
              class="mt-0.5 size-4 shrink-0 accent-brand-600 focus:outline-none dark:accent-brand-400" />
            <span class="min-w-0 flex-1">
              <span
                :id="`sso-metadata-cert-${index}-subject`"
                class="flex flex-wrap items-center gap-2">
                <span class="font-mono text-sm break-all text-gray-900 dark:text-white">
                  {{ cert.subject }}
                </span>
                <span
                  v-if="index === newestIndex"
                  data-testid="sso-metadata-cert-newest"
                  class="shrink-0 rounded-full bg-brand-50 px-2 py-0.5 text-[10px] font-medium tracking-wide text-brand-700 uppercase ring-1 ring-brand-600/20 ring-inset dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30">
                  {{ t('web.organizations.sso.metadata_cert_newest') }}
                </span>
              </span>
              <span
                :id="`sso-metadata-cert-${index}-details`"
                class="mt-1 block space-y-1 text-sm text-gray-600 dark:text-gray-300">
                <span
                  data-testid="sso-metadata-cert-validity"
                  class="block">
                  {{ validityText(cert) }}
                </span>
                <span class="block">
                  <span
                    data-testid="sso-metadata-cert-sha256-label"
                    class="font-medium">
                    {{ t('web.organizations.sso.metadata_cert_fingerprint_sha256') }}:
                  </span>
                  <code
                    data-testid="sso-metadata-cert-sha256"
                    class="font-mono text-xs break-all">
                    {{ cert.fingerprint_sha256 }}
                  </code>
                </span>
                <span class="block">
                  <span
                    data-testid="sso-metadata-cert-sha1-label"
                    class="font-medium">
                    {{ t('web.organizations.sso.metadata_cert_thumbprint_sha1') }}:
                  </span>
                  <code
                    data-testid="sso-metadata-cert-sha1"
                    class="font-mono text-xs break-all">
                    {{ cert.thumbprint_sha1 }}
                  </code>
                </span>
                <span
                  v-if="cert.problem !== null"
                  data-testid="sso-metadata-cert-problem"
                  class="block font-medium text-red-700 dark:text-red-300">
                  {{ cert.problem }}
                </span>
              </span>
            </span>
          </component>
        </div>
      </div>

      <!-- Advertised NameID formats: information only. The record's NameID
           policy is the admin's and is never changed from metadata. -->
      <div data-testid="sso-metadata-name-id-formats">
        <p class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.organizations.sso.metadata_name_id_formats') }}
        </p>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.metadata_name_id_formats_hint') }}
        </p>
        <ul
          v-if="response.name_id_formats.length > 0"
          class="mt-1 space-y-0.5">
          <li
            v-for="(format, index) in response.name_id_formats"
            :key="`${index}-${format}`"
            data-testid="sso-metadata-name-id-format"
            class="font-mono text-xs break-all text-gray-700 dark:text-gray-300">
            {{ format }}
          </li>
        </ul>
        <p
          v-else
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.metadata_name_id_formats_none') }}
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <button
          type="button"
          data-testid="sso-metadata-apply"
          :disabled="!canApply"
          :aria-describedby="selectionPending ? 'sso-metadata-select-hint' : undefined"
          @click="emit('apply')"
          class="inline-flex shrink-0 items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-600 dark:text-gray-100 dark:ring-gray-500 dark:hover:bg-gray-500">
          {{ t('web.organizations.sso.metadata_apply') }}
        </button>
        <p
          v-if="selectionPending"
          id="sso-metadata-select-hint"
          data-testid="sso-metadata-select-hint"
          class="text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.metadata_select_certificate') }}
        </p>
        <p
          v-else-if="applied"
          data-testid="sso-metadata-applied"
          role="status"
          class="text-sm text-green-700 dark:text-green-300">
          {{ t('web.organizations.sso.metadata_applied') }}
        </p>
      </div>
    </section>
  </div>
</template>
