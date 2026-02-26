// tests/unit/vue/fixtures/conceal-response.fixture.ts

import { mockMetadataRecord, mockSecretRecord } from './metadata.fixture';
import type { ConcealDataResponse } from '@/schemas/api';

export const mockConcealDataResponse: ConcealDataResponse = {
  success: true,
  custid: 'customer123',
  shrimp: 'test-shrimp-token',
  record: {
    metadata: mockMetadataRecord,
    secret: mockSecretRecord,
    share_domain: 'example.com',
  },
};

export const mockConcealDataResponseWithPassphrase: ConcealDataResponse = {
  ...mockConcealDataResponse,
  record: {
    ...mockConcealDataResponse.record,
    secret: {
      ...mockSecretRecord,
      has_passphrase: true,
    },
  },
};
