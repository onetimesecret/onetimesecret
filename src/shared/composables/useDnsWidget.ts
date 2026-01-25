// src/shared/composables/useDnsWidget.ts

//
// Composable for integrating the Approximated DNS widget into Vue components.
// The widget helps users configure DNS records by detecting their DNS provider
// and offering automated updates or provider-specific instructions.

import type { AxiosInstance } from 'axios';
import { inject, onUnmounted, ref, type Ref } from 'vue';

// Import widget assets - Vite will handle bundling/hashing
import dnsWidgetCss from '@/assets/approximated/dnswidget.v1.css?url';
import dnsWidgetJs from '@/assets/approximated/dnswidget.v1.js?url';

// DNS widget global interface
declare global {
  interface Window {
    apxDns?: {
      init: (config: DnsWidgetConfig) => void;
      stop: () => void;
      restart: () => void;
      config?: DnsWidgetConfig;
    };
  }
}

export interface DnsRecord {
  type: 'A' | 'CNAME' | 'TXT';
  host: string; // '@' for apex, or subdomain without trailing dot
  value: string;
  ttl?: number;
}

export interface DnsWidgetConfig {
  token: string;
  api_url: string;
  widget_id?: string;
  dnsRecords: DnsRecord[];
  domain?: string; // Pre-set domain, skips domain entry UI
  prefillDomain?: string; // Pre-fill domain input without skipping
  verifyAutoScroll?: boolean;
}

export interface DnsWidgetTokenResponse {
  success: boolean;
  token: string;
  api_url: string;
  expires_in: number;
}

export interface UseDnsWidgetOptions {
  /** Element ID where widget will be mounted */
  widgetId?: string;
  /** DNS records to configure */
  dnsRecords: DnsRecord[];
  /** Pre-set domain (skips domain entry step) */
  domain?: string;
  /** Pre-fill domain input */
  prefillDomain?: string;
  /** Auto-scroll to verification results */
  verifyAutoScroll?: boolean;
  /** Callback when user submits a domain */
  onDomainSubmit?: (domain: string) => void;
  /** Callback when widget flow is restarted */
  onRestart?: () => void;
  /** Callback when all records are verified */
  onRecordsVerified?: (records: unknown[]) => void;
  /** Callback when verification fails */
  onVerificationFailed?: (records: unknown[]) => void;
  /** Callback when only some records are verified */
  onPartialVerification?: (records: unknown[]) => void;
}

/**
 * Composable for managing the Approximated DNS widget
 *
 * @example
 * ```vue
 * <script setup>
 * const { isLoading, error, initWidget } = useDnsWidget({
 *   dnsRecords: [{ type: 'A', host: '@', value: '123.456.789.01', ttl: 3600 }],
 *   domain: 'example.com',
 *   onRecordsVerified: () => console.log('DNS configured!')
 * });
 *
 * onMounted(() => initWidget());
 * </script>
 *
 * <template>
 *   <div id="apxdnswidget"></div>
 * </template>
 * ```
 */
/* eslint-disable max-lines-per-function */
export function useDnsWidget(options: UseDnsWidgetOptions) {
  const $api = inject('api') as AxiosInstance;

  const isLoading = ref(false);
  const error: Ref<string | null> = ref(null);
  const isInitialized = ref(false);
  const widgetId = options.widgetId ?? 'apxdnswidget';

  // Event handlers
  const handleDomainSubmit = (event: CustomEvent<string>) => {
    options.onDomainSubmit?.(event.detail);
  };

  const handleRestart = () => {
    options.onRestart?.();
  };

  const handleRecordsVerified = (event: CustomEvent<unknown[]>) => {
    options.onRecordsVerified?.(event.detail);
  };

  const handleVerificationFailed = (event: CustomEvent<unknown[]>) => {
    options.onVerificationFailed?.(event.detail);
  };

  const handlePartialVerification = (event: CustomEvent<unknown[]>) => {
    options.onPartialVerification?.(event.detail);
  };

  /**
   * Fetch a DNS widget token from the backend
   */
  const fetchToken = async (): Promise<DnsWidgetTokenResponse | null> => {
    try {
      const response = await $api.get<DnsWidgetTokenResponse>('/api/domains/dns-widget/token');
      return response.data;
    } catch (err) {
      console.error('[useDnsWidget] Failed to fetch token:', err);
      return null;
    }
  };

  /**
   * Load the DNS widget script and CSS
   */
  const loadAssets = async (): Promise<boolean> => {
    // Check if already loaded
    if (window.apxDns) {
      return true;
    }

    return new Promise((resolve) => {
      // Load CSS (using Vite-resolved URL)
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = dnsWidgetCss;
      document.head.appendChild(link);

      // Load JS (using Vite-resolved URL)
      const script = document.createElement('script');
      script.src = dnsWidgetJs;
      script.onload = () => resolve(true);
      script.onerror = () => {
        console.error('[useDnsWidget] Failed to load widget script');
        resolve(false);
      };
      document.head.appendChild(script);
    });
  };

  /**
   * Register event listeners for widget events
   */
  const registerEventListeners = () => {
    document.addEventListener(
      'apx-dnswidget-user-submitted-domain',
      handleDomainSubmit as EventListener
    );
    document.addEventListener('apx-dnswidget-restarted', handleRestart);
    document.addEventListener(
      'apx-dnswidget-records-completely-verified',
      handleRecordsVerified as EventListener
    );
    document.addEventListener(
      'apx-dnswidget-records-failed-verification',
      handleVerificationFailed as EventListener
    );
    document.addEventListener(
      'apx-dnswidget-records-partially-verified',
      handlePartialVerification as EventListener
    );
  };

  /**
   * Remove event listeners
   */
  const removeEventListeners = () => {
    document.removeEventListener(
      'apx-dnswidget-user-submitted-domain',
      handleDomainSubmit as EventListener
    );
    document.removeEventListener('apx-dnswidget-restarted', handleRestart);
    document.removeEventListener(
      'apx-dnswidget-records-completely-verified',
      handleRecordsVerified as EventListener
    );
    document.removeEventListener(
      'apx-dnswidget-records-failed-verification',
      handleVerificationFailed as EventListener
    );
    document.removeEventListener(
      'apx-dnswidget-records-partially-verified',
      handlePartialVerification as EventListener
    );
  };

  /**
   * Initialize the DNS widget
   */
  const initWidget = async (): Promise<boolean> => {
    if (isInitialized.value) {
      return true;
    }

    isLoading.value = true;
    error.value = null;

    try {
      // Load assets
      const assetsLoaded = await loadAssets();
      if (!assetsLoaded) {
        error.value = 'Failed to load DNS widget';
        return false;
      }

      // Fetch token
      const tokenData = await fetchToken();
      if (!tokenData?.token) {
        error.value = 'DNS widget not available';
        return false;
      }

      // Ensure widget element exists
      const widgetEl = document.getElementById(widgetId);
      if (!widgetEl) {
        error.value = `Widget element #${widgetId} not found`;
        return false;
      }

      // Register event listeners
      registerEventListeners();

      // Initialize widget
      const config: DnsWidgetConfig = {
        token: tokenData.token,
        api_url: tokenData.api_url,
        widget_id: widgetId,
        dnsRecords: options.dnsRecords,
        verifyAutoScroll: options.verifyAutoScroll ?? true,
      };

      if (options.domain) {
        config.domain = options.domain;
      } else if (options.prefillDomain) {
        config.prefillDomain = options.prefillDomain;
      }

      window.apxDns?.init(config);
      isInitialized.value = true;
      return true;
    } catch (err) {
      console.error('[useDnsWidget] Initialization error:', err);
      error.value = 'Failed to initialize DNS widget';
      return false;
    } finally {
      isLoading.value = false;
    }
  };

  /**
   * Stop and clear the widget
   */
  const stopWidget = () => {
    if (window.apxDns) {
      window.apxDns.stop();
    }
    removeEventListeners();
    isInitialized.value = false;
  };

  /**
   * Restart the widget flow
   */
  const restartWidget = () => {
    if (window.apxDns) {
      window.apxDns.restart();
    }
  };

  // Cleanup on unmount
  onUnmounted(() => {
    stopWidget();
  });

  return {
    isLoading,
    error,
    isInitialized,
    initWidget,
    stopWidget,
    restartWidget,
    fetchToken,
  };
}
