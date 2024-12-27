// tests/unit/vue/fixtures/metadata.ts
import type { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { MetadataState } from '@/schemas/models/metadata';

export const mockMetadataRecord: Metadata = {
  key: 'testkey123',
  shortkey: 'abc123',
  secret_shortkey: 'xyz789',
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
};

export const mockReceivedMetadataDetails: MetadataDetails = {
  ...mockMetadataDetails,
  is_received: true,
  show_metadata_link: false,
};

export const mockOrphanedMetadataRecord: Metadata = {
  ...mockMetadataRecord,
  state: MetadataState.ORPHANED,
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
