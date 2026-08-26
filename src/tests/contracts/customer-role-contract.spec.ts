// src/tests/contracts/customer-role-contract.spec.ts
//
// Contract tests keeping the frontend role vocabulary in sync with the
// backend's assignable roles, and pinning the degradation behavior for
// values outside it (#4298 / FRONTEND-19V).
//
// The backend's single source of truth for assignable roles is
// Auth::Operations::Customers::SetRole::VALID_ROLES
// (apps/web/auth/operations/customers/set_role.rb) — every value there is
// writable to a live customer record via `bin/ots customers role promote`.
// The frontend enum silently missed `admin`/`staff`, so a promoted account
// failed the whole AccountResponse parse and /account/settings/api rendered
// the error boundary. These tests read VALID_ROLES from the Ruby source, so
// a backend role the frontend cannot parse fails CI instead of production.

import {
  customerRoleResilientSchema,
  customerRoleSchema,
  customerRoleValues,
} from '@/schemas/contracts/customer';
import { customerSchema as v3CustomerSchema } from '@/schemas/shapes/v3/customer';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

// ---------------------------------------------------------------------------
// Backend source extraction
// ---------------------------------------------------------------------------

const SET_ROLE_SOURCE_PATH = fileURLToPath(
  new URL('../../../apps/web/auth/operations/customers/set_role.rb', import.meta.url)
);

/**
 * Extracts VALID_ROLES from the Ruby op's source.
 *
 * Throws (failing the suite loudly) if the file moves or the declaration
 * changes shape — a silent empty list would make every assertion below
 * vacuously pass.
 */
function backendAssignableRoles(): string[] {
  const source = readFileSync(SET_ROLE_SOURCE_PATH, 'utf8');
  const match = source.match(/VALID_ROLES\s*=\s*%w\[([^\]]*)\]/);
  if (!match) {
    throw new Error(
      `Could not extract VALID_ROLES from ${SET_ROLE_SOURCE_PATH}. ` +
        'If the declaration moved or changed shape, update this test AND ' +
        'verify customerRoleValues still covers every assignable role.'
    );
  }
  return match[1].trim().split(/\s+/).filter(Boolean);
}

/** Minimal valid V3 customer record (mirrors account.spec.ts fixture). */
const validCustomerBase = {
  identifier: 'cust:abc123',
  created: 1700000000,
  updated: 1700000000,
  objid: 'abc123',
  extid: '',
  role: 'customer',
  email: 'user@example.com',
  verified: true,
  active: true,
  secrets_created: 0,
  secrets_burned: 0,
  secrets_shared: 0,
  emails_sent: 0,
  last_login: null,
  locale: 'en',
  notify_on_reveal: false,
  feature_flags: {},
};

// ---------------------------------------------------------------------------
// Vocabulary sync (frontend ⊇ backend-assignable)
// ---------------------------------------------------------------------------

describe('Customer role contract (SetRole::VALID_ROLES)', () => {
  const backendRoles = backendAssignableRoles();

  it('extraction found a plausible role list', () => {
    // Guard against regex rot: the backend list must at minimum contain the
    // two roles the product cannot function without.
    expect(backendRoles).toContain('colonel');
    expect(backendRoles).toContain('customer');
  });

  it.each(backendRoles)(
    'backend-assignable role "%s" is in customerRoleValues',
    (role) => {
      expect(customerRoleValues).toContain(role);
    }
  );

  it.each(backendRoles)(
    'backend-assignable role "%s" parses through the strict role schema',
    (role) => {
      expect(customerRoleSchema.parse(role)).toBe(role);
    }
  );

  it('frontend-only roles are documented lifecycle values', () => {
    // Values the frontend knows but the CLI cannot assign. Each is set by a
    // backend feature rather than the SetRole op. If this list grows,
    // document where the new value comes from.
    const lifecycleRoles: Record<string, string> = {
      recipient: 'Read-only secret recipient',
      user_deleted_self: 'right_to_be_forgotten feature (lib/onetime/models/features)',
      anonymous: 'Customer#anonymous? sentinel (lib/onetime/models/customer.rb)',
    };
    const frontendOnly = customerRoleValues.filter((r) => !backendRoles.includes(r));
    expect(frontendOnly.filter((r) => !(r in lifecycleRoles))).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Degradation behavior (role must never be parse-blocking)
// ---------------------------------------------------------------------------

describe('customerRoleResilientSchema degradation', () => {
  it('degrades an unknown role to "customer"', () => {
    expect(customerRoleResilientSchema.parse('superuser')).toBe('customer');
  });

  it('degrades a null role (legacy Redis hash without the field) to "customer"', () => {
    expect(customerRoleResilientSchema.parse(null)).toBe('customer');
    expect(customerRoleResilientSchema.parse(undefined)).toBe('customer');
  });

  it('passes known roles through unchanged', () => {
    for (const role of customerRoleValues) {
      expect(customerRoleResilientSchema.parse(role)).toBe(role);
    }
  });

  it('a full customer record with an unknown role parses with role degraded', () => {
    // The #4298 failure mode: the role value must degrade the badge, never
    // fail the record parse and take down the settings page.
    const result = v3CustomerSchema.parse({ ...validCustomerBase, role: 'superuser' });
    expect(result.role).toBe('customer');
  });

  it('a full customer record with a CLI-assigned role keeps it', () => {
    const result = v3CustomerSchema.parse({ ...validCustomerBase, role: 'admin' });
    expect(result.role).toBe('admin');
  });
});
