// src/tests/schemas/shapes/fixtures/feedback.fixtures.ts
//
// Feedback test fixtures using factory pattern.
// Feedback is a simple entity with msg, stamp (Date), and a details boolean.
//
// Note: Canonical stamp is a Date object. V2 wire format uses string,
// V3 wire format uses number (Unix epoch seconds).

import type {
  FeedbackCanonical,
  FeedbackDetailsCanonical,
} from '@/schemas/contracts/feedback';
import {
  toV2WireFeedback,
  toV2WireFeedbackDetails,
  toV3WireFeedback,
  toV3WireFeedbackDetails,
  type V2WireFeedback,
  type V2WireFeedbackDetails,
  type V3WireFeedback,
  type V3WireFeedbackDetails,
} from '../helpers/serializers';

// -----------------------------------------------------------------------------
// Constants for round-second timestamps
// -----------------------------------------------------------------------------

/** Base timestamp: 2024-01-15T10:00:00.000Z */
const BASE_TIMESTAMP = new Date('2024-01-15T10:00:00.000Z');

// -----------------------------------------------------------------------------
// Canonical Factories
// -----------------------------------------------------------------------------

/**
 * Creates a canonical feedback object with sensible defaults.
 * All timestamps are round seconds for epoch conversion safety.
 */
export function createCanonicalFeedback(
  overrides?: Partial<FeedbackCanonical>
): FeedbackCanonical {
  return {
    msg: 'This is a test feedback message for the application.',
    stamp: BASE_TIMESTAMP,
    ...overrides,
  };
}

/**
 * Creates canonical feedback details for display metadata.
 */
export function createCanonicalFeedbackDetails(
  overrides?: Partial<FeedbackDetailsCanonical>
): FeedbackDetailsCanonical {
  return {
    received: false,
    ...overrides,
  };
}

// -----------------------------------------------------------------------------
// Edge Case Factories
// -----------------------------------------------------------------------------

/**
 * Creates feedback with maximum message length.
 */
export function createMaxLengthFeedback(
  overrides?: Partial<FeedbackCanonical>
): FeedbackCanonical {
  return createCanonicalFeedback({
    msg: 'A'.repeat(1500), // Max length per V2 schema
    ...overrides,
  });
}

/**
 * Creates feedback with minimum message length.
 */
export function createMinLengthFeedback(
  overrides?: Partial<FeedbackCanonical>
): FeedbackCanonical {
  return createCanonicalFeedback({
    msg: 'X', // Min length per V2 schema (min 1)
    ...overrides,
  });
}

/**
 * Creates feedback with received=true in details.
 */
export function createReceivedFeedbackDetails(
  overrides?: Partial<FeedbackDetailsCanonical>
): FeedbackDetailsCanonical {
  return createCanonicalFeedbackDetails({
    received: true,
    ...overrides,
  });
}

// -----------------------------------------------------------------------------
// Wire Format Factories (use serializers)
// -----------------------------------------------------------------------------

/**
 * Creates V2 wire format from canonical.
 */
export function createV2WireFeedback(
  canonical?: FeedbackCanonical
): V2WireFeedback {
  return toV2WireFeedback(canonical ?? createCanonicalFeedback());
}

export function createV2WireFeedbackDetails(
  canonical?: FeedbackDetailsCanonical
): V2WireFeedbackDetails {
  return toV2WireFeedbackDetails(canonical ?? createCanonicalFeedbackDetails());
}

/**
 * Creates V3 wire format from canonical.
 */
export function createV3WireFeedback(
  canonical?: FeedbackCanonical
): V3WireFeedback {
  return toV3WireFeedback(canonical ?? createCanonicalFeedback());
}

export function createV3WireFeedbackDetails(
  canonical?: FeedbackDetailsCanonical
): V3WireFeedbackDetails {
  return toV3WireFeedbackDetails(canonical ?? createCanonicalFeedbackDetails());
}

// -----------------------------------------------------------------------------
// Comparison Functions
// -----------------------------------------------------------------------------

/**
 * Compares two canonical feedback objects for equality.
 * Handles Date comparison by converting to timestamps.
 */
export function compareCanonicalFeedback(
  a: FeedbackCanonical,
  b: FeedbackCanonical
): { equal: boolean; differences: string[] } {
  const differences: string[] = [];

  if (a.msg !== b.msg) {
    differences.push(`msg: ${JSON.stringify(a.msg)} !== ${JSON.stringify(b.msg)}`);
  }

  // Compare stamp as timestamps (handles Date objects)
  const aStamp = a.stamp instanceof Date ? a.stamp.getTime() : a.stamp;
  const bStamp = b.stamp instanceof Date ? b.stamp.getTime() : b.stamp;
  if (aStamp !== bStamp) {
    differences.push(`stamp: ${aStamp} !== ${bStamp}`);
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}

/**
 * Compares two canonical feedback details for equality.
 */
export function compareCanonicalFeedbackDetails(
  a: FeedbackDetailsCanonical,
  b: FeedbackDetailsCanonical
): { equal: boolean; differences: string[] } {
  const differences: string[] = [];

  if (a.received !== b.received) {
    differences.push(`received: ${JSON.stringify(a.received)} !== ${JSON.stringify(b.received)}`);
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}
