// src/tests/schemas/api/auth/billing-redirect.spec.ts

// Tests for the billing_redirect verdict shared by the create-account, login
// and two-factor completion schemas. The backend sends valid: false with the
// missing half as null when only one of product/interval was submitted
// (apps/web/auth/config/hooks/billing.rb, build_billing_redirect_info).

import { describe, it, expect } from 'vitest';
import {
  createAccountResponseSchema,
  hasBillingRedirect,
  loginResponseSchema,
  otpVerifyResponseSchema,
} from '@/schemas/api/auth/responses/auth';

const noInterval = {
  product: 'identity_plus_v1',
  interval: null,
  valid: false,
  error: 'Missing product or interval',
};

const noProduct = {
  product: null,
  interval: 'monthly',
  valid: false,
  error: 'Missing product or interval',
};

const resolved = { product: 'identity_plus_v1', interval: 'monthly', valid: true };

describe('createAccountResponseSchema billing_redirect', () => {
  it.each([
    ['no interval', noInterval],
    ['no product', noProduct],
  ])('parses a verdict with %s and keeps it', (_label, verdict) => {
    const body = { success: 'Account created', next_action: 'sign_in', billing_redirect: verdict };

    expect(createAccountResponseSchema.parse(body)).toEqual(body);
  });

  it('parses an invalid verdict without an error message', () => {
    const body = {
      success: 'Account created',
      next_action: 'verify_email',
      billing_redirect: { product: 'retired-plan', interval: 'monthly', valid: false },
    };

    expect(createAccountResponseSchema.parse(body)).toEqual(body);
  });

  it('rejects a valid verdict with a missing half', () => {
    const result = createAccountResponseSchema.safeParse({
      success: 'Account created',
      next_action: 'sign_in',
      billing_redirect: { product: 'x', interval: null, valid: true },
    });

    expect(result.success).toBe(false);
  });
});

describe('loginResponseSchema billing_redirect', () => {
  it('parses a complete verdict as a valid billing redirect', () => {
    const parsed = loginResponseSchema.parse({ success: 'ok', billing_redirect: resolved });

    expect(parsed).toEqual({ success: 'ok', billing_redirect: resolved });
    expect(hasBillingRedirect(parsed)).toBe(true);
  });

  it('keeps a partial verdict as the invalid member', () => {
    const parsed = loginResponseSchema.parse({ success: 'ok', billing_redirect: noInterval });

    expect(parsed).toEqual({ success: 'ok', billing_redirect: noInterval });
    expect(hasBillingRedirect(parsed)).toBe(false);
  });

  it('keeps mfa_required alongside a partial verdict', () => {
    const body = { success: 'ok', mfa_required: true, billing_redirect: noProduct };

    expect(loginResponseSchema.parse(body)).toEqual(body);
  });
});

describe('otpVerifyResponseSchema billing_redirect', () => {
  it('parses a complete verdict', () => {
    const body = { success: 'ok', billing_redirect: resolved };

    expect(otpVerifyResponseSchema.parse(body)).toEqual(body);
  });

  it('parses a partial verdict', () => {
    const body = { success: 'ok', billing_redirect: noInterval };

    expect(otpVerifyResponseSchema.parse(body)).toEqual(body);
  });
});
