// src/tests/fixtures/incomingConfig.fixture.ts
//
// Test fixtures for the domain incoming-secrets configuration.
// All recipients use the plaintext admin-view shape; the legacy hashed
// `{digest, display_name}` shape was removed alongside the
// IncomingSecretsConfig backend.

import type { DomainIncomingRecipient } from '@/schemas/shapes/domains/incoming-config';
import type { IncomingConfigFormState } from '@/shared/composables/useIncomingConfig';

// ---------------------------------------------------------------------------
// Recipient fixtures (plaintext)
// ---------------------------------------------------------------------------

export const validRecipientInput: DomainIncomingRecipient = {
  email: 'new@example.com',
  name: 'New Recipient',
};

export const validRecipientInputNoName: DomainIncomingRecipient = {
  email: 'another@example.com',
  name: 'another',
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
// Form-state fixtures
// ---------------------------------------------------------------------------

export const emptyFormState: IncomingConfigFormState = {
  enabled: false,
  recipients: [],
};

export const singleRecipientFormState: IncomingConfigFormState = {
  enabled: true,
  recipients: [{ email: 'security@acme.com', name: 'Security Team' }],
};

export const multipleRecipientsFormState: IncomingConfigFormState = {
  enabled: true,
  recipients: [
    { email: 'security@acme.com', name: 'Security Team' },
    { email: 'support@acme.com', name: 'Support' },
    { email: 'alerts@acme.com', name: 'alerts' },
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
  recipients: Array.from({ length: 19 }, (_, i) => ({
    email: `recipient${i + 1}@acme.com`,
    name: `Recipient ${i + 1}`,
  })),
};

// ---------------------------------------------------------------------------
// Service response fixtures (what IncomingConfigService returns)
// ---------------------------------------------------------------------------

export const mockEmptyConfigResponse = {
  record: {
    domain_id: 'dom_test_123',
    enabled: false,
    recipients: [] as DomainIncomingRecipient[],
    max_recipients: 20,
    created_at: null,
    updated_at: null,
  },
};

export const mockSingleRecipientConfigResponse = {
  record: {
    domain_id: 'dom_test_123',
    enabled: true,
    recipients: [{ email: 'security@acme.com', name: 'Security Team' }],
    max_recipients: 20,
    created_at: new Date('2026-01-01T00:00:00Z'),
    updated_at: new Date('2026-01-01T00:00:00Z'),
  },
};

export const mockMultipleRecipientsConfigResponse = {
  record: {
    domain_id: 'dom_test_123',
    enabled: true,
    recipients: [
      { email: 'security@acme.com', name: 'Security Team' },
      { email: 'support@acme.com', name: 'Support' },
    ],
    max_recipients: 20,
    created_at: new Date('2026-01-01T00:00:00Z'),
    updated_at: new Date('2026-01-15T00:00:00Z'),
  },
};

// ---------------------------------------------------------------------------
// Raw API envelope fixtures (for schema validation tests)
// ---------------------------------------------------------------------------

export const mockGetIncomingConfigApiResponse = {
  record: {
    domain_id: 'dom_test_123',
    enabled: true,
    recipients: [
      { email: 'security@acme.com', name: 'Security Team' },
      { email: 'support@acme.com', name: 'Support' },
    ],
    max_recipients: 20,
    created_at: 1735689600,
    updated_at: 1736899200,
  },
  details: {
    can_manage: true,
    feature_available: true,
  },
};

export const mockEmptyIncomingConfigApiResponse = {
  record: {
    domain_id: 'dom_test_123',
    enabled: false,
    recipients: [],
    max_recipients: 20,
    created_at: null,
    updated_at: null,
  },
  details: {
    can_manage: true,
    feature_available: true,
  },
};
