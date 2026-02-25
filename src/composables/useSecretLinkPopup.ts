// src/composables/useSecretLinkPopup.ts

import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { WindowService } from '@/services/window.service';
import { useMetadataStore } from '@/stores/metadataStore';
import { type ConcealDataResponse } from '@/schemas/api/responses';

export interface SecretLinkModalData {
  shareUrl: string;
  naturalExpiration: string;
  hasPassphrase: boolean;
  metadataKey: string;
  secretShortkey: string;
}

/**
 * useSecretLinkPopup
 *
 * Encapsulates the popup dialog workflow for secret creation.
 * After a secret is created, instead of navigating to /receipt/:key,
 * this composable builds modal data and shows a popup with the share
 * link so the user can copy it immediately.
 *
 * Also marks the metadata as viewed so the receipt page won't reveal
 * secret content if visited later.
 */
export function useSecretLinkPopup() {
  const { t } = useI18n();
  const metadataStore = useMetadataStore();

  const showModal = ref(false);
  const modalData = ref<SecretLinkModalData | null>(null);

  /**
   * Build the share URL from available conceal response data.
   * The conceal endpoint doesn't return computed fields like share_url,
   * so we construct it the same way SecretLinksTableRow does.
   */
  function buildShareUrl(response: ConcealDataResponse): string {
    const siteHost = WindowService.get('site_host');
    const customDomain = response.record.metadata.share_domain;
    // Use the custom domain when set, otherwise fall back to the current
    // origin so the link matches the host the user is actually visiting
    // (avoids port mismatches in dev where site_host differs from the proxy).
    const shareDomain = customDomain && customDomain !== siteHost
      ? customDomain
      : window.location.host;
    const protocol = window.location.protocol;
    return `${protocol}//${shareDomain}/secret/${response.record.secret.key}`;
  }

  /**
   * Format TTL seconds into a human-readable expiration string.
   * The conceal endpoint doesn't return natural_expiration.
   */
  function formatTtl(seconds: number): string {
    const units: { key: string; seconds: number }[] = [
      { key: 'day', seconds: 86400 },
      { key: 'hour', seconds: 3600 },
      { key: 'minute', seconds: 60 },
    ];
    for (const unit of units) {
      const count = Math.floor(seconds / unit.seconds);
      if (count >= 1) {
        return t('web.UNITS.ttl.duration', {
          count,
          unit: t(`web.UNITS.ttl.time.${unit.key}`, count),
        });
      }
    }
    return t('web.UNITS.ttl.duration', {
      count: seconds,
      unit: t('web.UNITS.ttl.time.second', seconds),
    });
  }

  /**
   * Handle a successful secret creation by building modal data,
   * showing the popup, and marking metadata as viewed.
   */
  function handleSecretCreated(response: ConcealDataResponse) {
    const metadataKey = response.record.metadata.key;

    modalData.value = {
      shareUrl: buildShareUrl(response),
      naturalExpiration: formatTtl(response.record.metadata.secret_ttl ?? 0),
      hasPassphrase: !!response.record.secret.has_passphrase,
      metadataKey,
      secretShortkey: response.record.metadata.secret_shortkey ?? '',
    };
    showModal.value = true;

    // Mark the metadata as viewed so the receipt page won't reveal the
    // secret content on its first load. Without this, skipping the
    // immediate navigation to /receipt/:key leaves the record in "new"
    // state and the secret leaks when the page is eventually visited.
    metadataStore.fetch(metadataKey).catch(() => {
      // Silently ignore — the modal already has everything it needs.
    });
  }

  function handleCloseModal() {
    showModal.value = false;
    modalData.value = null;
  }

  return {
    showModal,
    modalData,
    buildShareUrl,
    formatTtl,
    handleSecretCreated,
    handleCloseModal,
  };
}
