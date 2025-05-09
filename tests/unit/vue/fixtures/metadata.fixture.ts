// tests/unit/vue/fixtures/metadata.fixture.ts

import { MetadataState } from '@/schemas/models/metadata';
import { Secret, SecretState } from '@/schemas/models/secret';
import type { Metadata, MetadataDetails } from '@/schemas/models/metadata';

/**
 * Metadata fixtures for testing and merriment
 *
 * Relationship quick reference:
 *
 * 1. `mockMetadataRecord`:
 *    - `secret_key: 'secret-test-key-123'`
 *    - `secret_shortkey: 'secret-abc123'`
 *
 * 2. `mockBurnedMetadataRecord`:
 *    - `secret_key: 'secret-burned-key-123'`
 *    - `secret_shortkey: 'secret-burned-abc123'`
 *
 * 3. `mockReceivedMetadataRecord`:
 *    - `secret_key: 'secret-received-key-123'`
 *    - `secret_shortkey: 'secret-received-abc123'`
 *
 * 4. `mockOrphanedMetadataRecord`:
 *    - `secret_key: 'secret-orphaned-key-123'`
 *    - `secret_shortkey: 'secret-orphaned-abc123'`
 *
 * 5. In `mockMetadataRecordsList`, each record also has unique `secret_key` and `secret_shortkey`:
 *    - Received records:
 *      - `secret-received-1` / `sec-rcv1`
 *      - `secret-received-2` / `sec-rcv2`
 *    - Not received record:
 *      - `secret-not-received-1` / `sec-nrcv1`
 *
 *  Every metadata record expects to have exactly one reference to a secret
 *  record, via secret_key and secret_short_key. Review and make sure all
 *  metadata objects have a singular standalone secret to refer to.
 *
 *  To fully implement the 1:1 relationship, we created corresponding mock
 *  secret objects that match the secret schema. Please review for
 *  completeness and correctness.
 *
 *  NOTE: DO NOT ADD `mockSecretRecordsList` into the fixtures. Ensure
 *  that the secret records are correctly defined and referenced in the
 *  metadata fixtures only. This is a security feature.
 *
 */
export const mockMetadataRecord: Metadata = {
  key: 'testkey123',
  shortkey: 'abc123',
  secret_key: 'secret-test-key-123', // Added
  secret_shortkey: 'secret-abc123', // Added
  state: MetadataState.NEW,
  natural_expiration: '24 hours',
  expiration: new Date('2024-12-26T00:06:54Z'),
  expiration_in_seconds: 86400,
  share_path: '/share/abc123',
  burn_path: '/burn/abc123',
  metadata_path: '/metadata/abc123',
  share_url: 'https://example.com/share/abc123',
  metadata_url: 'https://example.com/metadata/abc123',
  burn_url: 'https://example.com/burn/abc123',
  identifier: 'test-identifier',
  is_viewed: false,
  is_received: false,
  is_burned: false,
  is_destroyed: false,
  is_expired: false,
  is_orphaned: false,
  burned: null,
  received: null,
  created: new Date('2024-12-25T16:06:54Z'),
  updated: new Date('2024-12-26T09:06:54Z'),
  secret_ttl: null,
  metadata_ttl: null,
  lifespan: null,
};

export const mockMetadataDetails: MetadataDetails = {
  type: 'record',

  display_lines: 1,
  no_cache: false,
  secret_realttl: 86400,
  maxviews: 1,
  has_maxviews: true,
  view_count: 0,
  has_passphrase: false,
  can_decrypt: true,
  secret_value: 'test-secret',
  show_secret: true,
  show_secret_link: true,
  show_metadata_link: true,
  show_metadata: true,
  show_recipients: false,
};

export const mockBurnedMetadataRecord: Metadata = {
  ...mockMetadataRecord,
  key: 'burnedkey',
  shortkey: 'b123',
  state: MetadataState.BURNED,
  burned: new Date('2024-12-25T16:06:54Z'),
  secret_key: 'secret-burned-key-123', // Updated
  secret_shortkey: 'secret-burned-abc123', // Updated
  is_burned: true,
};

export const mockBurnedMetadataDetails: MetadataDetails = {
  ...mockMetadataDetails,
  show_secret: false,
  show_secret_link: false,
  can_decrypt: false,
  secret_value: null,
};

export const mockReceivedMetadataRecord: Metadata = {
  ...mockMetadataRecord,
  key: 'receivedkey',
  shortkey: 'rcv123',
  state: MetadataState.RECEIVED,
  received: new Date('2024-12-25T16:06:54Z'),
  secret_key: 'secret-received-key-123', // Updated
  secret_shortkey: 'secret-received-abc123', // Updated
  is_received: true,
};

export const mockReceivedMetadataDetails: MetadataDetails = {
  ...mockMetadataDetails,
  show_metadata_link: false,
};

export const mockOrphanedMetadataRecord: Metadata = {
  ...mockMetadataRecord,
  key: 'orphanedkey',
  shortkey: 'orphan123',
  state: MetadataState.ORPHANED,
  secret_key: 'secret-orphaned-key-123',
  secret_shortkey: 'secret-orphaned-abc123', // Changed from 'so-abc123'
  is_orphaned: true,
};

export const mockOrphanedMetadataDetails: MetadataDetails = {
  ...mockMetadataDetails,
  show_secret: false,
  show_secret_link: false,
  can_decrypt: false,
  secret_value: null,
};

// Helper function to create metadata with passphrase
export const createMetadataWithPassphrase = (
  passphrase: string
): { record: Metadata; details: MetadataDetails } => ({
  record: mockMetadataRecord,
  details: {
    ...mockMetadataDetails,
    has_passphrase: true,
    secret_value: null,
    can_decrypt: false,
  },
});

export const mockMetadataRecentRecords = [
  // Should be an array, not an object
  {
    custid: 'customer123',
    secret_ttl: 3600,
    show_recipients: true,
    is_received: false,
    is_burned: false,
    is_orphaned: true,
    is_destroyed: false,
    is_truncated: true,
    identifier: 'abc123def456',
    // Add these required fields from metadataBaseSchema
    state: 'new',
    key: 'key123',
    shortkey: 'short123',
    created: new Date(),
    updated: new Date(),
  },
];

export const mockMetadataRecentDetails = {
  type: 'list',
  since: Date.now(),
  now: new Date(),
  has_items: true,
  received: [
    {
      key: 'received-metadata-1',
      shortkey: 'rcv-short-1',
      secret_shortkey: 'sec-rcv-1',
      custid: 'user-789',
      secret_ttl: 1800, // 30 minutes
      state: MetadataState.RECEIVED,
      created: new Date('2024-12-25T16:06:54Z'),
      updated: new Date('2024-12-26T09:06:54Z'),
      show_recipients: false,
      is_received: true,
      is_burned: false,
      is_orphaned: false,
      is_destroyed: false,
      is_truncated: false,
      identifier: 'received-metadata-1',
    },
  ],
  notreceived: [
    {
      key: 'not-received-metadata-1',
      shortkey: 'nrcv-short-1',
      secret_shortkey: 'sec-nrcv-1',
      custid: 'user-101',
      secret_ttl: 5400, // 1.5 hours
      state: MetadataState.NEW,
      created: new Date('2024-12-25T16:06:54Z'),
      updated: new Date('2024-12-26T09:06:54Z'),
      show_recipients: false,
      is_received: false,
      is_burned: false,
      is_orphaned: false,
      is_destroyed: false,
      is_truncated: false,
      identifier: 'not-received-metadata-1',
    },
  ],
};

export const mockMetadataRecent = {
  records: mockMetadataRecentRecords,
  details: mockMetadataRecentDetails,
};

export const mockSecretRecord: Secret = {
  key: 'testkey123',
  shortkey: 'abc123',
  state: SecretState.NEW,
  identifier: 'testkey123',
  created: new Date(),
  updated: new Date(),
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'test-secret',
  secret_ttl: 86400,
  // Schema expects number, not string
  lifespan: 86400,
};

export const mockBurnedSecretRecord: Secret | null = null;

export const mockReceivedSecretRecord: Secret = {
  key: 'secret-received-key-123',
  shortkey: 'secret-received-abc123',
  state: SecretState.RECEIVED,
  identifier: 'testkey123',
  created: new Date(),
  updated: new Date(),
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'received test secret',
  secret_ttl: 86400,
  lifespan: 86400,
};

export const mockOrphanedSecretRecord: Secret = {
  key: 'secret-orphaned-key-123',
  shortkey: 'secret-orphaned-abc123',
  state: SecretState.VIEWED,
  identifier: 'testkey123',
  created: new Date(),
  updated: new Date(),
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'orphaned test secret',
  // Schema now expects number, not null
  secret_ttl: 0,
  lifespan: 0,
};

export const mockReceivedSecretRecord1: Secret = {
  key: 'secret-received-1',
  shortkey: 'sec-rcv1',
  state: SecretState.RECEIVED,
  identifier: 'testkey123',
  created: new Date(),
  updated: new Date(),
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'received-test-secret-1',
  secret_ttl: 3600, // 1 hour
  lifespan: 3600,
};

export const mockReceivedSecretRecord2: Secret = {
  key: 'secret-received-2',
  shortkey: 'sec-rcv2',
  state: SecretState.RECEIVED,
  identifier: 'testkey123',
  created: new Date(),
  updated: new Date(),
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'received-test-secret-2',
  secret_ttl: 7200, // 2 hours
  lifespan: 7200,
};

export const mockNotReceivedSecretRecord1: Secret = {
  key: 'secret-not-received-1',
  shortkey: 'sec-nrcv1',
  state: SecretState.NEW,
  identifier: 'testkey123',
  created: new Date(),
  updated: new Date(),
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'not-received-test-secret-1',
  secret_ttl: 1800, // 30 minutes
  lifespan: 1800,
};

export const mockSecretResponse = {
  success: true,
  record: { ...mockSecretRecord }, // This part is fine
  details: {
    continue: false,
    show_secret: false,
    correct_passphrase: false,
    display_lines: 1,
    one_liner: true,
    is_owner: false, // Add this field to match schema
  },
};

export const mockSecretRevealed = {
  ...mockSecretResponse,
  record: {
    ...mockSecretRecord,
    secret_value: 'revealed secret',
  },
  details: {
    ...mockSecretResponse.details,
    show_secret: true,
    correct_passphrase: true,
    is_owner: false, // Add this field to match schema
  },
};

export const mockSecretDetails = {
  continue: false,
  is_owner: false,
  show_secret: false,
  correct_passphrase: false,
  display_lines: 1,
  one_liner: true,
};
