// src/tests/schemas/api/v3/responses/account.spec.ts
//
// Regression tests for #2699: V3 customer schema rejects string-encoded
// counter fields from Redis, hiding the API token.
//
// The backend sends counter fields (secrets_created, secrets_burned,
// secrets_shared, emails_sent) as Redis-encoded strings ("0" not 0).
// Before the fix, z.number().default(0) rejected the entire customer
// record, causing accountStore.fetch() to fail silently.

import { describe, it, expect } from 'vitest';
import {
  customerRecord,
  accountResponseSchema,
  customerResponseSchema,
} from '@/schemas/api/v3/responses/account';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Minimal valid customer record with numeric counters (pre-Redis encoding). */
const validCustomerBase = {
  identifier: 'cust:abc123',
  created: 1700000000,
  updated: 1700000000,
  objid: 'abc123',
  extid: '',
  role: 'customer' as const,
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

/** Same record but with string-encoded counters (the Redis/backend reality). */
const redisEncodedCustomer = {
  ...validCustomerBase,
  secrets_created: '5',
  secrets_burned: '2',
  secrets_shared: '3',
  emails_sent: '10',
};

// ---------------------------------------------------------------------------
// customerRecord (inner schema)
// ---------------------------------------------------------------------------

describe('customerRecord', () => {
  describe('counter field coercion (#2699)', () => {
    it('accepts string-encoded counter fields from Redis', () => {
      const result = customerRecord.parse(redisEncodedCustomer);

      expect(result.secrets_created).toBe(5);
      expect(result.secrets_burned).toBe(2);
      expect(result.secrets_shared).toBe(3);
      expect(result.emails_sent).toBe(10);
    });

    it('accepts numeric counter fields directly', () => {
      const result = customerRecord.parse(validCustomerBase);

      expect(result.secrets_created).toBe(0);
      expect(result.secrets_burned).toBe(0);
      expect(result.secrets_shared).toBe(0);
      expect(result.emails_sent).toBe(0);
    });

    it('coerces string "0" to number 0', () => {
      const input = { ...validCustomerBase, secrets_created: '0' };
      const result = customerRecord.parse(input);

      expect(result.secrets_created).toBe(0);
      expect(typeof result.secrets_created).toBe('number');
    });

    it('coerces large string counters', () => {
      const input = { ...validCustomerBase, secrets_created: '9999' };
      const result = customerRecord.parse(input);

      expect(result.secrets_created).toBe(9999);
    });
  });

  describe('counter field defaults', () => {
    it('defaults missing counter fields to 0', () => {
      const { secrets_created, secrets_burned, secrets_shared, emails_sent, ...withoutCounters } =
        validCustomerBase;

      const result = customerRecord.parse(withoutCounters);

      expect(result.secrets_created).toBe(0);
      expect(result.secrets_burned).toBe(0);
      expect(result.secrets_shared).toBe(0);
      expect(result.emails_sent).toBe(0);
    });

    it('defaults undefined counter fields to 0', () => {
      const input = {
        ...validCustomerBase,
        secrets_created: undefined,
        secrets_burned: undefined,
        secrets_shared: undefined,
        emails_sent: undefined,
      };
      const result = customerRecord.parse(input);

      expect(result.secrets_created).toBe(0);
      expect(result.secrets_burned).toBe(0);
      expect(result.secrets_shared).toBe(0);
      expect(result.emails_sent).toBe(0);
    });
  });

  describe('counter field rejection of non-numeric strings', () => {
    // z.coerce.number() in Zod v4 rejects NaN results, so non-numeric
    // strings like "abc" correctly fail validation.
    it('rejects non-numeric string "abc"', () => {
      const input = { ...validCustomerBase, secrets_created: 'abc' };
      expect(() => customerRecord.parse(input)).toThrow();
    });

    it('coerces empty string to 0', () => {
      // z.coerce.number() converts "" to 0 via Number("")
      const input = { ...validCustomerBase, secrets_created: '' };
      const result = customerRecord.parse(input);

      expect(result.secrets_created).toBe(0);
    });
  });

  describe('timestamp transforms', () => {
    it('converts created/updated epoch seconds to Date objects', () => {
      const result = customerRecord.parse(validCustomerBase);

      expect(result.created).toBeInstanceOf(Date);
      expect(result.updated).toBeInstanceOf(Date);
      expect(result.created.getTime()).toBe(1700000000 * 1000);
    });

    it('handles null last_login', () => {
      const result = customerRecord.parse(validCustomerBase);
      expect(result.last_login).toBeNull();
    });

    it('converts numeric last_login to Date', () => {
      const input = { ...validCustomerBase, last_login: 1700000000 };
      const result = customerRecord.parse(input);

      expect(result.last_login).toBeInstanceOf(Date);
    });
  });

  describe('role validation', () => {
    it.each(['customer', 'colonel', 'recipient', 'user_deleted_self'] as const)(
      'accepts role "%s"',
      (role) => {
        const input = { ...validCustomerBase, role };
        const result = customerRecord.parse(input);
        expect(result.role).toBe(role);
      }
    );

    it('rejects invalid role', () => {
      const input = { ...validCustomerBase, role: 'admin' };
      expect(() => customerRecord.parse(input)).toThrow();
    });
  });

  describe('boolean fields', () => {
    it('accepts boolean verified/active fields', () => {
      const result = customerRecord.parse(validCustomerBase);

      expect(result.verified).toBe(true);
      expect(result.active).toBe(true);
    });

    it('defaults notify_on_reveal to false when missing', () => {
      const { notify_on_reveal, ...withoutNotify } = validCustomerBase;
      const result = customerRecord.parse(withoutNotify);

      expect(result.notify_on_reveal).toBe(false);
    });

    it('accepts optional contributor field', () => {
      const input = { ...validCustomerBase, contributor: true };
      const result = customerRecord.parse(input);

      expect(result.contributor).toBe(true);
    });
  });
});

// ---------------------------------------------------------------------------
// accountResponseSchema (envelope-wrapped)
// ---------------------------------------------------------------------------

describe('accountResponseSchema', () => {
  describe('full record parsing (#2699 regression)', () => {
    it('parses account response with string-encoded customer counters', () => {
      const apiResponse = {
        record: {
          cust: redisEncodedCustomer,
          apitoken: 'tok_abc123def456',
        },
      };

      const result = accountResponseSchema.parse(apiResponse);

      expect(result.record.apitoken).toBe('tok_abc123def456');
      expect(result.record.cust.secrets_created).toBe(5);
      expect(result.record.cust.secrets_burned).toBe(2);
      expect(result.record.cust.secrets_shared).toBe(3);
      expect(result.record.cust.emails_sent).toBe(10);
    });

    it('parses account response with numeric customer counters', () => {
      const apiResponse = {
        record: {
          cust: validCustomerBase,
          apitoken: 'tok_abc123def456',
        },
      };

      const result = accountResponseSchema.parse(apiResponse);

      expect(result.record.apitoken).toBe('tok_abc123def456');
      expect(result.record.cust.secrets_created).toBe(0);
    });

    it('parses account response with null apitoken', () => {
      const apiResponse = {
        record: {
          cust: validCustomerBase,
          apitoken: null,
        },
      };

      const result = accountResponseSchema.parse(apiResponse);

      expect(result.record.apitoken).toBeNull();
    });

    it('includes optional envelope fields', () => {
      const apiResponse = {
        user_id: 'cust123',
        shrimp: 'csrf_token_value',
        record: {
          cust: validCustomerBase,
          apitoken: 'tok_abc123',
        },
      };

      const result = accountResponseSchema.parse(apiResponse);

      expect(result.user_id).toBe('cust123');
      expect(result.shrimp).toBe('csrf_token_value');
    });
  });

  describe('validation failures', () => {
    it('rejects response missing cust field', () => {
      const apiResponse = {
        record: {
          apitoken: 'tok_abc123',
        },
      };

      expect(() => accountResponseSchema.parse(apiResponse)).toThrow();
    });

    it('rejects response missing record field', () => {
      expect(() => accountResponseSchema.parse({})).toThrow();
    });
  });
});

// ---------------------------------------------------------------------------
// customerResponseSchema (envelope-wrapped with checkAuthDetails)
// ---------------------------------------------------------------------------

describe('customerResponseSchema', () => {
  it('parses customer response with string-encoded counters and auth details', () => {
    const apiResponse = {
      record: redisEncodedCustomer,
      details: {
        authenticated: true,
        authorized: true,
      },
    };

    const result = customerResponseSchema.parse(apiResponse);

    expect(result.record.secrets_created).toBe(5);
    expect(result.details?.authenticated).toBe(true);
    expect(result.details?.authorized).toBe(true);
  });

  it('parses customer response without details', () => {
    const apiResponse = {
      record: validCustomerBase,
    };

    const result = customerResponseSchema.parse(apiResponse);

    expect(result.record.email).toBe('user@example.com');
    expect(result.details).toBeUndefined();
  });
});
