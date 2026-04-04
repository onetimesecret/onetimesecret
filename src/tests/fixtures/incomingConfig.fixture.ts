// src/tests/fixtures/incomingConfig.fixture.ts
//
// Test fixtures for domain incoming secrets recipients configuration.
// Used by composable and component tests.

import type { DomainRecipientInput } from '@/schemas/api/domains/requests/domain-recipients';
import type { DomainRecipientResponse } from '@/schemas/api/domains/responses/domain-recipients';
import type { IncomingConfigFormState, IncomingConfigServerState } from '@/shared/composables/useIncomingConfig';

// ---------------------------------------------------------------------------
// Form State Fixtures (plaintext emails for user input)
// ---------------------------------------------------------------------------

export const emptyFormState: IncomingConfigFormState = {
  enabled: false,
  recipients: [],
};

export const singleRecipientFormState: IncomingConfigFormState = {
  enabled: true,
  recipients: [
    { email: 'security@acme.com', name: 'Security Team' },
  ],
};

export const multipleRecipientsFormState: IncomingConfigFormState = {
  enabled: true,
  recipients: [
    { email: 'security@acme.com', name: 'Security Team' },
    { email: 'support@acme.com', name: 'Support' },
    { email: 'alerts@acme.com' },
  ],
};

export const maxRecipientsFormState: IncomingConfigFormState = {
  enabled: true,
  recipients: Array.from({ length: 20 }, (_, i) => ({
    email: `recipient${i + 1}@acme.com`,
    name: `Recipient ${i + 1}`,
  })),
};

export const nearLimitFormState: IncomingConfigFormState = {
  enabled: true,
  recipients: Array.from({ length: 18 }, (_, i) => ({
    email: `recipient${i + 1}@acme.com`,
    name: `Recipient ${i + 1}`,
  })),
};

// ---------------------------------------------------------------------------
// Server State Fixtures (hashed digests from API responses)
// ---------------------------------------------------------------------------

export const emptyServerState: IncomingConfigServerState = {
  recipients: [],
};

export const singleRecipientServerState: IncomingConfigServerState = {
  recipients: [
    { digest: 'sha256_abc123', display_name: 'Security Team' },
  ],
};

export const multipleRecipientsServerState: IncomingConfigServerState = {
  recipients: [
    { digest: 'sha256_abc123', display_name: 'Security Team' },
    { digest: 'sha256_def456', display_name: 'Support' },
    { digest: 'sha256_ghi789', display_name: '' },
  ],
};

export const maxRecipientsServerState: IncomingConfigServerState = {
  recipients: Array.from({ length: 20 }, (_, i) => ({
    digest: `sha256_digest${i + 1}`,
    display_name: `Recipient ${i + 1}`,
  })),
};

// ---------------------------------------------------------------------------
// API Response Fixtures
// ---------------------------------------------------------------------------

export const mockRecipientsResponse = {
  recipients: multipleRecipientsServerState.recipients,
  canManage: true,
  maxRecipients: 20,
};

export const mockEmptyRecipientsResponse = {
  recipients: [],
  canManage: true,
  maxRecipients: 20,
};

export const mockPutRecipientsResponse = {
  recipients: [
    { digest: 'sha256_new123', display_name: 'New Recipient' },
  ],
  canManage: true,
  maxRecipients: 20,
};

export const mockDeleteRecipientsResponse = {
  success: true,
  message: 'Recipients deleted successfully',
};

// ---------------------------------------------------------------------------
// Input Data Fixtures
// ---------------------------------------------------------------------------

export const validRecipientInput: DomainRecipientInput = {
  email: 'new@example.com',
  name: 'New Recipient',
};

export const validRecipientInputNoName: DomainRecipientInput = {
  email: 'another@example.com',
};

export const invalidEmailInputs = [
  'not-an-email',
  'missing@',
  '@nodomain.com',
  'spaces in@email.com',
  '',
];

export const validEmailInputs = [
  'simple@example.com',
  'user.name@example.com',
  'user+tag@example.com',
  'user@subdomain.example.com',
];

// ---------------------------------------------------------------------------
// Raw API Response Fixtures (for schema validation tests)
// ---------------------------------------------------------------------------

export const mockGetRecipientsApiResponse = {
  record: {
    recipients: multipleRecipientsServerState.recipients,
  },
  details: {
    can_manage: true,
    max_recipients: 20,
  },
};

export const mockPutRecipientsApiResponse = {
  record: {
    recipients: [
      { digest: 'sha256_new123', display_name: 'New Recipient' },
    ],
  },
  details: {
    can_manage: true,
    max_recipients: 20,
  },
};

export const mockDeleteRecipientsApiResponse = {
  success: true,
  message: 'Recipients deleted successfully',
};
