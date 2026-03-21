// src/tests/schemas/shapes/fixtures/secret.fixtures.ts
//
// Secret test fixtures using factory pattern.
// All timestamps use round seconds to survive epoch conversion.

import type {
  SecretBaseCanonical,
  SecretCanonical,
  SecretWithTimestampsCanonical,
  SecretDetailsCanonical,
  SecretState,
} from '@/schemas/contracts';
import {
  toV2WireSecretBase,
  toV2WireSecret,
  toV2WireSecretDetails,
  toV3WireSecretBase,
  toV3WireSecret,
  toV3WireSecretDetails,
  type V2WireSecretBase,
  type V2WireSecret,
  type V2WireSecretDetails,
  type V3WireSecretBase,
  type V3WireSecret,
  type V3WireSecretDetails,
} from '../helpers/serializers';

// ─────────────────────────────────────────────────────────────────────────────
// Constants for round-second timestamps
// ─────────────────────────────────────────────────────────────────────────────

/** Base timestamp: 2024-01-15T10:00:00.000Z */
const BASE_TIMESTAMP = new Date('2024-01-15T10:00:00.000Z');

/** One hour after base */
const ONE_HOUR_LATER = new Date('2024-01-15T11:00:00.000Z');

// ─────────────────────────────────────────────────────────────────────────────
// Canonical Factories
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates a canonical secret base with sensible defaults.
 * This is the minimal secret record without TTL or timestamps.
 */
export function createCanonicalSecretBase(
  overrides?: Partial<SecretBaseCanonical>
): SecretBaseCanonical {
  return {
    identifier: 's3cr3t12ab34',
    key: 's3cr3t12ab34',
    shortid: 's3cr3t12',
    state: 'new' as SecretState,
    has_passphrase: false,
    verification: false,
    secret_value: undefined,

    // State boolean fields
    is_previewed: false,
    is_revealed: false,

    ...overrides,
  };
}

/**
 * Creates a canonical full secret with TTL fields.
 */
export function createCanonicalSecret(
  overrides?: Partial<SecretCanonical>
): SecretCanonical {
  const base = createCanonicalSecretBase(overrides);
  return {
    ...base,
    secret_ttl: 3600,
    lifespan: 86400,
    ...overrides,
  };
}

/**
 * Creates a canonical secret with timestamps (V3 format).
 * All timestamps are round seconds for epoch conversion safety.
 */
export function createCanonicalSecretWithTimestamps(
  overrides?: Partial<SecretWithTimestampsCanonical>
): SecretWithTimestampsCanonical {
  const secret = createCanonicalSecret(overrides);
  return {
    ...secret,
    created: BASE_TIMESTAMP,
    updated: BASE_TIMESTAMP,
    ...overrides,
  };
}

/**
 * Creates canonical secret details for display metadata.
 */
export function createCanonicalSecretDetails(
  overrides?: Partial<SecretDetailsCanonical>
): SecretDetailsCanonical {
  return {
    continue: true,
    is_owner: false,
    show_secret: true,
    correct_passphrase: true,
    display_lines: 5,
    one_liner: null,
    ...overrides,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// State-Specific Factories
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates a "previewed" state secret (recipient viewed the confirmation page).
 */
export function createPreviewedSecret(
  overrides?: Partial<SecretCanonical>
): SecretCanonical {
  return createCanonicalSecret({
    state: 'previewed' as SecretState,
    is_previewed: true,
    ...overrides,
  });
}

/**
 * Creates a "revealed" state secret (secret content was decrypted).
 */
export function createRevealedSecret(
  overrides?: Partial<SecretCanonical>
): SecretCanonical {
  return createCanonicalSecret({
    state: 'revealed' as SecretState,
    is_previewed: true,
    is_revealed: true,
    ...overrides,
  });
}

/**
 * Creates a "burned" state secret (secret was destroyed before reveal).
 */
export function createBurnedSecret(
  overrides?: Partial<SecretCanonical>
): SecretCanonical {
  return createCanonicalSecret({
    state: 'burned' as SecretState,
    ...overrides,
  });
}

/**
 * Creates a secret with passphrase protection.
 */
export function createPassphraseProtectedSecret(
  overrides?: Partial<SecretCanonical>
): SecretCanonical {
  return createCanonicalSecret({
    has_passphrase: true,
    ...overrides,
  });
}

/**
 * Creates a secret with verification enabled.
 */
export function createVerificationEnabledSecret(
  overrides?: Partial<SecretCanonical>
): SecretCanonical {
  return createCanonicalSecret({
    verification: true,
    ...overrides,
  });
}

/**
 * Creates a secret with a value (for revealed state).
 */
export function createSecretWithValue(
  overrides?: Partial<SecretCanonical>
): SecretCanonical {
  return createCanonicalSecret({
    state: 'revealed' as SecretState,
    is_revealed: true,
    secret_value: 'This is my secret message',
    ...overrides,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Harness (for reusable round-trip pattern)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Compares two canonical secret bases for equality.
 */
export function compareCanonicalSecretBase(
  a: SecretBaseCanonical,
  b: SecretBaseCanonical
): { equal: boolean; differences: string[] } {
  const differences: string[] = [];

  // All fields in SecretBaseCanonical
  const fields = [
    'identifier',
    'key',
    'shortid',
    'state',
    'has_passphrase',
    'verification',
    'secret_value',
    'is_previewed',
    'is_revealed',
  ] as const;

  for (const field of fields) {
    if (a[field] !== b[field]) {
      differences.push(`${field}: ${JSON.stringify(a[field])} !== ${JSON.stringify(b[field])}`);
    }
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}

/**
 * Compares two canonical full secrets for equality.
 */
export function compareCanonicalSecret(
  a: SecretCanonical,
  b: SecretCanonical
): { equal: boolean; differences: string[] } {
  const baseResult = compareCanonicalSecretBase(a, b);
  const differences = [...baseResult.differences];

  // Additional full secret fields
  const additionalFields = ['secret_ttl', 'lifespan'] as const;

  for (const field of additionalFields) {
    if (a[field] !== b[field]) {
      differences.push(`${field}: ${JSON.stringify(a[field])} !== ${JSON.stringify(b[field])}`);
    }
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}

/**
 * Compares two canonical secrets with timestamps for equality.
 * Handles Date comparison by converting to timestamps.
 */
export function compareCanonicalSecretWithTimestamps(
  a: SecretWithTimestampsCanonical,
  b: SecretWithTimestampsCanonical
): { equal: boolean; differences: string[] } {
  const secretResult = compareCanonicalSecret(a, b);
  const differences = [...secretResult.differences];

  // Date fields (compare as timestamps)
  const dateFields = ['created', 'updated'] as const;

  for (const field of dateFields) {
    const aVal = a[field];
    const bVal = b[field];
    const aTime = aVal instanceof Date ? aVal.getTime() : aVal;
    const bTime = bVal instanceof Date ? bVal.getTime() : bVal;
    if (aTime !== bTime) {
      differences.push(`${field}: ${aTime} !== ${bTime}`);
    }
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}

/**
 * Compares two canonical secret details for equality.
 */
export function compareCanonicalSecretDetails(
  a: SecretDetailsCanonical,
  b: SecretDetailsCanonical
): { equal: boolean; differences: string[] } {
  const differences: string[] = [];

  const fields = [
    'continue',
    'is_owner',
    'show_secret',
    'correct_passphrase',
    'display_lines',
    'one_liner',
  ] as const;

  for (const field of fields) {
    if (a[field] !== b[field]) {
      differences.push(`${field}: ${JSON.stringify(a[field])} !== ${JSON.stringify(b[field])}`);
    }
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Wire Format Factories (use serializers)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates V2 wire format from canonical (with timestamps).
 */
export function createV2WireSecretBase(
  canonical?: SecretWithTimestampsCanonical
): V2WireSecretBase {
  return toV2WireSecretBase(canonical ?? createCanonicalSecretWithTimestamps());
}

export function createV2WireSecret(
  canonical?: SecretWithTimestampsCanonical
): V2WireSecret {
  return toV2WireSecret(canonical ?? createCanonicalSecretWithTimestamps());
}

export function createV2WireSecretDetails(
  canonical?: SecretDetailsCanonical
): V2WireSecretDetails {
  return toV2WireSecretDetails(canonical ?? createCanonicalSecretDetails());
}

/**
 * Creates V3 wire format from canonical.
 */
export function createV3WireSecretBase(
  canonical?: SecretWithTimestampsCanonical
): V3WireSecretBase {
  return toV3WireSecretBase(canonical ?? createCanonicalSecretWithTimestamps());
}

export function createV3WireSecret(
  canonical?: SecretWithTimestampsCanonical
): V3WireSecret {
  return toV3WireSecret(canonical ?? createCanonicalSecretWithTimestamps());
}

export function createV3WireSecretDetails(
  canonical?: SecretDetailsCanonical
): V3WireSecretDetails {
  return toV3WireSecretDetails(canonical ?? createCanonicalSecretDetails());
}
