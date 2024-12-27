// tests/unit/vue/fixtures/metadata.ts
import { Secret, SecretState } from '@/schemas';
import { Metadata, MetadataDetails, MetadataState } from '@/schemas/models/metadata';

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
  share_path: '/share/abc123',
  burn_path: '/burn/abc123',
  metadata_path: '/metadata/abc123',
  share_url: 'https://example.com/share/abc123',
  metadata_url: 'https://example.com/metadata/abc123',
  burn_url: 'https://example.com/burn/abc123',
  identifier: 'test-identifier',
  burned: null,
  received: null,
  created: new Date('2024-12-25T16:06:54Z'),
  updated: new Date('2024-12-26T09:06:54Z'),
};

export const mockMetadataDetails: MetadataDetails = {
  type: 'record',
  title: 'Test Secret',
  display_lines: 1,
  display_feedback: true,
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
  is_destroyed: false,
  is_received: false,
  is_burned: false,
  is_orphaned: false,
};

export const mockBurnedMetadataRecord: Metadata = {
  ...mockMetadataRecord,
  state: MetadataState.BURNED,
  burned: new Date('2024-12-25T16:06:54Z'),
  secret_key: 'secret-burned-key-123', // Updated
  secret_shortkey: 'secret-burned-abc123', // Updated
};

export const mockBurnedMetadataDetails: MetadataDetails = {
  ...mockMetadataDetails,
  is_burned: true,
  show_secret: false,
  show_secret_link: false,
  can_decrypt: false,
  secret_value: null,
};

export const mockReceivedMetadataRecord: Metadata = {
  ...mockMetadataRecord,
  state: MetadataState.RECEIVED,
  received: new Date('2024-12-25T16:06:54Z'),
  secret_key: 'secret-received-key-123', // Updated
  secret_shortkey: 'secret-received-abc123', // Updated
};

export const mockReceivedMetadataDetails: MetadataDetails = {
  ...mockMetadataDetails,
  is_received: true,
  show_metadata_link: false,
};

export const mockOrphanedMetadataRecord: Metadata = {
  ...mockMetadataRecord,
  state: MetadataState.ORPHANED,
  secret_key: 'secret-orphaned-key-123', // Updated
  secret_shortkey: 'secret-orphaned-abc123', // Updated
};

export const mockOrphanedMetadataDetails: MetadataDetails = {
  ...mockMetadataDetails,
  is_orphaned: true,
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

export const mockMetadataRecordsList = {
  type: 'list',
  since: Date.now(),
  now: new Date(),
  has_items: true,
  received: [
    {
      key: 'received-key-1',
      shortkey: 'rcv1',
      secret_key: 'secret-received-1',
      secret_shortkey: 'sec-rcv1',
      custid: 'user123',
      secret_ttl: 3600,
      state: MetadataState.RECEIVED,
      identifier: 'received-secret-1',
      is_received: true,
      is_burned: false,
      is_orphaned: false,
      is_destroyed: false,
      is_truncated: false,
      show_recipients: false,
    },
    {
      key: 'received-key-2',
      shortkey: 'rcv2',
      secret_key: 'secret-received-2',
      secret_shortkey: 'sec-rcv2',
      custid: 'user456',
      secret_ttl: 7200,
      state: MetadataState.RECEIVED,
      identifier: 'received-secret-2',
      is_received: true,
      is_burned: false,
      is_orphaned: false,
      is_destroyed: false,
      is_truncated: false,
      show_recipients: true,
    },
  ],
  notreceived: [
    {
      key: 'not-received-key-1',
      shortkey: 'nrcv1',
      secret_key: 'secret-not-received-1',
      secret_shortkey: 'sec-nrcv1',
      custid: 'user789',
      secret_ttl: 1800,
      state: MetadataState.NEW,
      identifier: 'pending-secret-1',
      is_received: false,
      is_burned: false,
      is_orphaned: false,
      is_destroyed: false,
      is_truncated: false,
      show_recipients: false,
    },
  ],
};

export const mockSecretRecord: Secret = {
  key: 'testkey123',
  shortkey: 'abc123',
  state: SecretState.NEW,
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'test-secret',
  secret_ttl: 86400,
  lifespan: '24 hours',
  original_size: '42 bytes',
};

export const mockBurnedSecretRecord: Secret = {
  key: 'secret-burned-key-123',
  shortkey: 'secret-burned-abc123',
  state: SecretState.BURNED,
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: null,
  secret_ttl: null,
  lifespan: null,
  original_size: '42 bytes',
};

export const mockReceivedSecretRecord: Secret = {
  key: 'secret-received-key-123',
  shortkey: 'secret-received-abc123',
  state: SecretState.RECEIVED,
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'received test secret',
  secret_ttl: 86400,
  lifespan: '24 hours',
  original_size: '42 bytes',
};

export const mockOrphanedSecretRecord: Secret = {
  key: 'secret-orphaned-key-123',
  shortkey: 'secret-orphaned-abc123',
  state: SecretState.VIEWED,
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: null,
  secret_ttl: null,
  lifespan: null,
  original_size: '42 bytes',
};

export const mockReceivedSecretRecord1: Secret = {
  key: 'secret-received-1',
  shortkey: 'sec-rcv1',
  state: SecretState.RECEIVED,
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'received-test-secret-1',
  secret_ttl: 3600, // 1 hour
  lifespan: '1 hour',
  original_size: '42 bytes',
};

export const mockReceivedSecretRecord2: Secret = {
  key: 'secret-received-2',
  shortkey: 'sec-rcv2',
  state: SecretState.RECEIVED,
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'received-test-secret-2',
  secret_ttl: 7200, // 2 hours
  lifespan: '2 hours',
  original_size: '42 bytes',
};

export const mockNotReceivedSecretRecord1: Secret = {
  key: 'secret-not-received-1',
  shortkey: 'sec-nrcv1',
  state: SecretState.NEW,
  is_truncated: false,
  has_passphrase: false,
  verification: true,
  secret_value: 'not-received-test-secret-1',
  secret_ttl: 1800, // 30 minutes
  lifespan: '30 minutes',
  original_size: '42 bytes',
};
