// src/tests/schemas/receiptStateTerminology.spec.ts

//
// TDD tests for secret state terminology rename: viewed->previewed, received->revealed
//
// These tests define the expected behavior BEFORE implementation.
// They should FAIL initially and pass after schema updates.

import { describe, expect, it } from 'vitest';
import {
  ReceiptState,
  receiptStateSchema,
  receiptBaseSchema,
  receiptSchema,
} from '@/schemas/models/receipt';
import { SecretState, secretStateSchema } from '@/schemas/models/secret';

describe('Receipt State Terminology Rename', () => {
  describe('ReceiptState enum values', () => {
    it('includes PREVIEWED state value', () => {
      // New terminology: viewed -> previewed
      expect(ReceiptState.PREVIEWED).toBe('previewed');
    });

    it('includes REVEALED state value', () => {
      // New terminology: received -> revealed
      expect(ReceiptState.REVEALED).toBe('revealed');
    });

    it('maintains backward compatibility with VIEWED (deprecated alias)', () => {
      // Backward compat: VIEWED should still exist as alias
      expect(ReceiptState.VIEWED).toBeDefined();
    });

    it('maintains backward compatibility with RECEIVED (deprecated alias)', () => {
      // Backward compat: RECEIVED should still exist as alias
      expect(ReceiptState.RECEIVED).toBeDefined();
    });
  });

  describe('receiptStateSchema validation', () => {
    it('accepts "previewed" as valid state', () => {
      const result = receiptStateSchema.safeParse('previewed');
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBe('previewed');
      }
    });

    it('accepts "revealed" as valid state', () => {
      const result = receiptStateSchema.safeParse('revealed');
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBe('revealed');
      }
    });

    it('still accepts "viewed" for backward compatibility', () => {
      // Backend may still send "viewed" during transition period
      const result = receiptStateSchema.safeParse('viewed');
      expect(result.success).toBe(true);
    });

    it('still accepts "received" for backward compatibility', () => {
      // Backend may still send "received" during transition period
      const result = receiptStateSchema.safeParse('received');
      expect(result.success).toBe(true);
    });

    it('still accepts existing valid states', () => {
      const existingStates = ['new', 'shared', 'burned', 'expired', 'orphaned'];
      existingStates.forEach((state) => {
        const result = receiptStateSchema.safeParse(state);
        expect(result.success, `State "${state}" should be valid`).toBe(true);
      });
    });

    it('rejects invalid states', () => {
      const result = receiptStateSchema.safeParse('invalid_state');
      expect(result.success).toBe(false);
    });
  });

  describe('receiptBaseSchema new timestamp fields', () => {
    const baseReceiptData = {
      identifier: 'test-identifier',
      key: 'test-key',
      shortid: 'abc123',
      secret_ttl: '3600',
      receipt_ttl: '7200',
      lifespan: '3600',
      state: 'new',
      created: 1735142814,
      updated: 1735204014,
      is_viewed: 'false',
      is_received: 'false',
      is_burned: 'false',
      is_destroyed: 'false',
      is_expired: 'false',
      is_orphaned: 'false',
    };

    it('parses "previewed" timestamp field', () => {
      const data = {
        ...baseReceiptData,
        previewed: '2024-12-25T16:06:54Z',
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.previewed).toBeInstanceOf(Date);
      }
    });

    it('parses "revealed" timestamp field', () => {
      const data = {
        ...baseReceiptData,
        revealed: '2024-12-25T16:06:54Z',
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.revealed).toBeInstanceOf(Date);
      }
    });

    it('parses null "previewed" timestamp', () => {
      const data = {
        ...baseReceiptData,
        previewed: null,
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.previewed).toBeNull();
      }
    });

    it('parses null "revealed" timestamp', () => {
      const data = {
        ...baseReceiptData,
        revealed: null,
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.revealed).toBeNull();
      }
    });

    it('still parses "viewed" timestamp for backward compatibility', () => {
      const data = {
        ...baseReceiptData,
        viewed: '2024-12-25T16:06:54Z',
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.viewed).toBeInstanceOf(Date);
      }
    });

    it('still parses "received" timestamp for backward compatibility', () => {
      const data = {
        ...baseReceiptData,
        received: '2024-12-25T16:06:54Z',
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.received).toBeInstanceOf(Date);
      }
    });
  });

  describe('receiptBaseSchema new boolean fields', () => {
    const baseReceiptData = {
      identifier: 'test-identifier',
      key: 'test-key',
      shortid: 'abc123',
      secret_ttl: '3600',
      receipt_ttl: '7200',
      lifespan: '3600',
      state: 'new',
      created: 1735142814,
      updated: 1735204014,
      is_burned: 'false',
      is_destroyed: 'false',
      is_expired: 'false',
      is_orphaned: 'false',
    };

    it('parses "is_previewed" boolean field (string "true")', () => {
      const data = {
        ...baseReceiptData,
        is_previewed: 'true',
        is_revealed: 'false',
        is_viewed: 'false',
        is_received: 'false',
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.is_previewed).toBe(true);
      }
    });

    it('parses "is_previewed" boolean field (string "false")', () => {
      const data = {
        ...baseReceiptData,
        is_previewed: 'false',
        is_revealed: 'false',
        is_viewed: 'false',
        is_received: 'false',
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.is_previewed).toBe(false);
      }
    });

    it('parses "is_revealed" boolean field (string "true")', () => {
      const data = {
        ...baseReceiptData,
        is_previewed: 'false',
        is_revealed: 'true',
        is_viewed: 'false',
        is_received: 'false',
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.is_revealed).toBe(true);
      }
    });

    it('parses "is_revealed" boolean field (string "false")', () => {
      const data = {
        ...baseReceiptData,
        is_previewed: 'false',
        is_revealed: 'false',
        is_viewed: 'false',
        is_received: 'false',
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.is_revealed).toBe(false);
      }
    });

    it('still parses "is_viewed" for backward compatibility', () => {
      const data = {
        ...baseReceiptData,
        is_viewed: 'true',
        is_received: 'false',
        is_previewed: 'false',
        is_revealed: 'false',
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.is_viewed).toBe(true);
      }
    });

    it('still parses "is_received" for backward compatibility', () => {
      const data = {
        ...baseReceiptData,
        is_viewed: 'false',
        is_received: 'true',
        is_previewed: 'false',
        is_revealed: 'false',
      };
      const result = receiptBaseSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.is_received).toBe(true);
      }
    });
  });

  describe('Full receipt schema with new terminology', () => {
    const fullReceiptData = {
      key: 'test-key',
      shortid: 'abc123',
      secret_identifier: 'secret-123',
      secret_shortid: 'sec-abc',
      secret_ttl: '3600',
      receipt_ttl: '7200',
      lifespan: '3600',
      state: 'previewed',
      created: 1735142814,
      updated: 1735204014,
      previewed: '2024-12-25T16:06:54Z',
      revealed: null,
      is_previewed: 'true',
      is_revealed: 'false',
      is_viewed: 'false',
      is_received: 'false',
      is_burned: 'false',
      is_destroyed: 'false',
      is_expired: 'false',
      is_orphaned: 'false',
      natural_expiration: '24 hours',
      expiration: 1735171614,
      expiration_in_seconds: '86400',
      share_path: '/share/abc123',
      burn_path: '/burn/abc123',
      receipt_path: '/receipt/abc123',
      share_url: 'https://example.com/share/abc123',
      receipt_url: 'https://example.com/receipt/abc123',
      burn_url: 'https://example.com/burn/abc123',
      identifier: 'test-identifier',
    };

    it('parses full receipt with previewed state', () => {
      const result = receiptSchema.safeParse(fullReceiptData);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.state).toBe('previewed');
        expect(result.data.is_previewed).toBe(true);
        expect(result.data.previewed).toBeInstanceOf(Date);
      }
    });

    it('parses full receipt with revealed state', () => {
      const revealedData = {
        ...fullReceiptData,
        state: 'revealed',
        previewed: '2024-12-25T14:00:00Z',
        revealed: '2024-12-25T16:06:54Z',
        is_previewed: 'true',
        is_revealed: 'true',
      };
      const result = receiptSchema.safeParse(revealedData);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.state).toBe('revealed');
        expect(result.data.is_revealed).toBe(true);
        expect(result.data.revealed).toBeInstanceOf(Date);
      }
    });
  });
});

describe('Secret State Terminology Rename', () => {
  describe('SecretState enum values', () => {
    it('includes PREVIEWED state value', () => {
      // New terminology: viewed -> previewed
      expect(SecretState.PREVIEWED).toBe('previewed');
    });

    it('includes REVEALED state value', () => {
      // New terminology: received -> revealed
      expect(SecretState.REVEALED).toBe('revealed');
    });

    it('maintains backward compatibility with VIEWED (deprecated alias)', () => {
      expect(SecretState.VIEWED).toBeDefined();
    });

    it('maintains backward compatibility with RECEIVED (deprecated alias)', () => {
      expect(SecretState.RECEIVED).toBeDefined();
    });
  });

  describe('secretStateSchema validation', () => {
    it('accepts "previewed" as valid state', () => {
      const result = secretStateSchema.safeParse('previewed');
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBe('previewed');
      }
    });

    it('accepts "revealed" as valid state', () => {
      const result = secretStateSchema.safeParse('revealed');
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBe('revealed');
      }
    });

    it('still accepts "viewed" for backward compatibility', () => {
      const result = secretStateSchema.safeParse('viewed');
      expect(result.success).toBe(true);
    });

    it('still accepts "received" for backward compatibility', () => {
      const result = secretStateSchema.safeParse('received');
      expect(result.success).toBe(true);
    });

    it('still accepts existing valid states', () => {
      const existingStates = ['new', 'burned'];
      existingStates.forEach((state) => {
        const result = secretStateSchema.safeParse(state);
        expect(result.success, `State "${state}" should be valid`).toBe(true);
      });
    });
  });
});
