// src/tests/apps/admin/checkoutLinkSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelCheckoutLinkRecordSchema,
  colonelCheckoutLinkResponseSchema,
} from '@/schemas/api/internal/responses/colonel';
import { responseSchemas } from '@/schemas/api/internal/responses/registry';

/**
 * Zod tripwire for POST /api/colonel/users/:user_id/checkout-link.
 *
 * Payload shape is the frozen frontend/backend contract for the colonel
 * "create checkout link" action: a mutation-ack envelope whose `record`
 * carries the Stripe Checkout session (URL is the deliverable) and whose
 * `details` reports the region configuration that produced it.
 */
function checkoutPayload() {
  return {
    shrimp: '',
    record: {
      checkout_url: 'https://checkout.stripe.com/c/pay/cs_test_a1b2c3',
      session_id: 'cs_test_a1b2c3',
      plan_id: 'identity_plus_v1_month',
      price_id: 'price_1QAbCdEfGh',
      expires_at: 1783464864, // Unix seconds (~24h after creation)
    },
    details: {
      region: 'eu',
    },
  };
}

describe('colonelCheckoutLinkResponseSchema (CreateCheckoutLink)', () => {
  it('parses the contract payload and keeps expires_at a bare number', () => {
    const result = colonelCheckoutLinkResponseSchema.safeParse(checkoutPayload());
    expect(result.success).toBe(true);
    if (!result.success) return;

    expect(result.data.record.checkout_url).toBe(
      'https://checkout.stripe.com/c/pay/cs_test_a1b2c3'
    );
    expect(result.data.record.expires_at).toBe(1783464864);
    expect(result.data.details.region).toBe('eu');
  });

  it('rejects a 2xx ack missing the checkout_url (the deliverable)', () => {
    const payload = checkoutPayload();
    // @ts-expect-error deliberate contract break
    delete payload.record.checkout_url;
    expect(colonelCheckoutLinkResponseSchema.safeParse(payload).success).toBe(false);
  });

  it('rejects a stringly-typed expires_at', () => {
    const payload = checkoutPayload();
    (payload.record as Record<string, unknown>).expires_at = '1783464864';
    expect(colonelCheckoutLinkResponseSchema.safeParse(payload).success).toBe(false);
  });

  it('rejects details missing region', () => {
    const payload = checkoutPayload();
    // @ts-expect-error deliberate contract break
    delete payload.details.region;
    expect(colonelCheckoutLinkResponseSchema.safeParse(payload).success).toBe(false);
  });

  it('every record field is required (no silently-optional drift)', () => {
    for (const field of ['session_id', 'plan_id', 'price_id', 'expires_at'] as const) {
      const record = { ...checkoutPayload().record } as Record<string, unknown>;
      delete record[field];
      expect(colonelCheckoutLinkRecordSchema.safeParse(record).success).toBe(false);
    }
  });

  it('is registered for OpenAPI generation', () => {
    expect(responseSchemas.colonelCheckoutLink).toBe(colonelCheckoutLinkResponseSchema);
  });
});
