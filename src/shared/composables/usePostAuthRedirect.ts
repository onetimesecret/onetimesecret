// src/shared/composables/usePostAuthRedirect.ts

import {
  hasBillingRedirect,
  type BillingRedirect,
  type CreateAccountResponse,
  type LoginResponse,
} from '@/schemas/api/auth/responses/auth';
import { loggingService } from '@/services/logging.service';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { isValidInternalPath } from '@/utils/redirect';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * WHERE A USER LANDS AFTER AUTHENTICATING — the single implementation
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Every primary-factor success path converges here: password login (useAuth),
 * magic link (useMagicLink), and passwordless WebAuthn (useWebAuthn). They
 * used to disagree — the passwordless flows hard-pushed '/' and silently
 * dropped both the plan intent and the ?redirect the user arrived with.
 *
 * PRECEDENCE (identical on the backend, do not reorder):
 *   1. a VALID billing/plan intent — response-supplied, else the product +
 *      interval query pair;
 *   2. a VALID internal ?redirect path;
 *   3. '/'.
 *
 * `redirect` deliberately rides in the QUERY, not history state: it must
 * survive a fresh entry (shared link, new tab, an emailed verification link
 * opened in another browser). It is blessed as non-PII — see
 * src/router/README.md "Query-string policy" and the ots/no-pii-in-query
 * eslint rule. One-shot UI signals go the other way, in history state.
 */
/* eslint-disable max-lines-per-function */
export function usePostAuthRedirect() {
  const route = useRoute();
  const router = useRouter();
  const { t } = useI18n();
  const bootstrapStore = useBootstrapStore();
  const notificationsStore = useNotificationsStore();
  const organizationStore = useOrganizationStore();

  /**
   * Gets the redirect path from query params if valid.
   *
   * @returns The redirect path if valid, undefined otherwise
   */
  function getRedirectParam(): string | undefined {
    const redirect = route.query.redirect;
    const redirectPath = typeof redirect === 'string' ? redirect : undefined;
    return isValidInternalPath(redirectPath) ? redirectPath : undefined;
  }

  /**
   * Extracts billing-related query params from the current route.
   * Used to forward product/interval selection through auth flows.
   *
   * Terminology note:
   * - `interval` = plan frequency choice (month, year) - user's selection
   * - `billing_cycle` = subscription parameter - returned by backend
   *
   * The backend translates interval → billing_cycle when creating the
   * billing_redirect response, aligning with Stripe's terminology where
   * "interval" is the price frequency and "billing_cycle" refers to
   * subscription billing dates.
   *
   * @returns Object with product and interval if present in query params
   */
  function getBillingParams(): { product?: string; interval?: string } {
    const params: { product?: string; interval?: string } = {};
    if (route.query.product && typeof route.query.product === 'string') {
      params.product = route.query.product;
    }
    if (route.query.interval && typeof route.query.interval === 'string') {
      params.interval = route.query.interval;
    }
    return params;
  }

  /**
   * Extracts billing params from login response or falls back to query params.
   * Returns null if backend marked the plan as invalid.
   *
   * @param response - Login response that may contain billing_redirect
   * @returns Billing params or null if invalid/not present
   */
  function extractBillingParams(
    response?: LoginResponse | CreateAccountResponse
  ): { product: string; interval: string } | null {
    if (response && hasBillingRedirect(response)) {
      // Backend validated the plan - use the response values
      loggingService.debug('[postAuthRedirect] Using validated billing redirect from response', {
        product: response.billing_redirect.product,
        interval: response.billing_redirect.interval,
      });
      return {
        product: response.billing_redirect.product,
        interval: response.billing_redirect.interval,
      };
    }

    if (response && 'billing_redirect' in response && response.billing_redirect) {
      // Backend returned billing_redirect but valid=false - do not redirect
      const billingRedirect = response.billing_redirect as BillingRedirect;
      loggingService.warn(
        '[postAuthRedirect] Billing redirect skipped - backend marked plan as invalid',
        {
          product: billingRedirect.product,
          interval: billingRedirect.interval,
          valid: billingRedirect.valid,
        }
      );
      return null;
    }

    // No billing_redirect in response - check query params as fallback
    const params = getBillingParams();
    if (params.product && params.interval) {
      return { product: params.product, interval: params.interval };
    }

    return null;
  }

  /**
   * Handles redirect for users with existing subscriptions.
   * @returns true if redirect was performed
   */
  async function handleExistingSubscription(
    orgExtid: string,
    currentPlanId: string,
    product: string,
    interval: string
  ): Promise<boolean> {
    // Plan IDs are canonical family IDs (e.g., 'identity_plus_v1') - compare directly
    if (currentPlanId === product) {
      // Already subscribed to the same plan - redirect to billing overview
      loggingService.info('[postAuthRedirect] User already subscribed to requested plan', {
        currentPlan: currentPlanId,
        requestedProduct: product,
      });
      notificationsStore.show(t('web.billing.already_subscribed'), 'info', 'top');
      await router.push(`/billing/${orgExtid}/overview`);
      return true;
    }

    // Subscribed to a different plan - redirect to plan change flow
    loggingService.info(
      '[postAuthRedirect] User has different subscription, redirecting to plans',
      {
        currentPlan: currentPlanId,
        requestedProduct: product,
      }
    );
    // Object form so vue-router encodes the values: product/interval can come
    // straight from route.query, and raw `&`/`=`/`#` must not become URL syntax.
    await router.push({
      path: `/billing/${orgExtid}/plans`,
      query: { product, interval, change: 'true' },
    });
    return true;
  }

  /**
   * Handles billing redirect after successful authentication.
   * Uses billing_redirect from login response if valid, otherwise falls back to route query params.
   * Returns true if redirect was performed, false otherwise.
   *
   * Safety checks:
   * 1. Validates billing_redirect.valid flag from backend
   * 2. Checks if user already has an active subscription
   * 3. Redirects appropriately based on subscription status
   *
   * @param response - Login response that may contain billing_redirect
   */
  async function handleBillingRedirect(
    response?: LoginResponse | CreateAccountResponse
  ): Promise<boolean> {
    // Extract and validate billing params
    const billingParams = extractBillingParams(response);
    if (!billingParams) {
      return false;
    }
    const { product, interval } = billingParams;

    // Check if billing is enabled (graceful degradation for self-hosted)
    if (!bootstrapStore.billing_enabled) {
      loggingService.debug('[postAuthRedirect] Billing redirect skipped - billing not enabled');
      return false;
    }

    try {
      // Fetch organizations to get the default org's extid and subscription status
      await organizationStore.fetchOrganizations();
      const org = organizationStore.restorePersistedSelection();

      if (!org?.extid) {
        loggingService.warn('[postAuthRedirect] Billing redirect skipped - no organization found');
        return false;
      }

      // The org record from /api/organizations carries the subscription plan
      const currentPlanId = org.planid;

      // Check subscription status - delegate to helper if subscribed
      if (currentPlanId) {
        return handleExistingSubscription(org.extid, currentPlanId, product, interval);
      }

      // No active subscription - proceed to plans page for checkout
      loggingService.debug('[postAuthRedirect] Redirecting to billing plans', {
        org: org.extid,
        product,
        interval,
      });
      await router.push({
        path: `/billing/${org.extid}/plans`,
        query: { product, interval },
      });
      return true;
    } catch (err) {
      // Graceful degradation - if billing redirect fails, continue to dashboard
      loggingService.error(new Error(`Billing redirect failed: ${err}`));
      return false;
    }
  }

  /**
   * Navigates to wherever this user should land now that the primary factor is
   * proven and the session is established. Applies the precedence documented
   * at the top of this module.
   *
   * Callers that still have a pending second factor must NOT use this — they
   * forward `redirect` to /mfa-verify and let MfaChallenge finish the job.
   *
   * @param response - login/create-account body, when the caller has one
   */
  async function navigateAfterAuth(
    response?: LoginResponse | CreateAccountResponse
  ): Promise<void> {
    // Check for billing redirect using response data (validated by backend).
    // This handles both billing_redirect in response and fallback to query params.
    const redirected = await handleBillingRedirect(response);
    if (redirected) return;

    // Check for redirect param (e.g., from invitation flow)
    const redirectPath = getRedirectParam();
    if (redirectPath) {
      loggingService.debug('[postAuthRedirect] Redirecting to saved path', { redirectPath });
      await router.push(redirectPath);
      return;
    }

    await router.push('/');
  }

  return {
    getRedirectParam,
    getBillingParams,
    handleBillingRedirect,
    navigateAfterAuth,
  };
}
