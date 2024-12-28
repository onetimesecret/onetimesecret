// tests/unit/fixtures/domains.ts
import type { Domain } from '@/schemas/models/domain';

export const mockDomains: Record<string, Domain> = {
  'domain-1': {
    id: 'domain-1',
    name: 'example.com',
    status: 'verified',
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  },
  'domain-2': {
    id: 'domain-2',
    name: 'test.com',
    status: 'pending',
    createdAt: '2024-01-02T00:00:00Z',
    updatedAt: '2024-01-02T00:00:00Z',
  },
};

export const newDomainData = {
  name: 'new-domain.com',
  id: 'domain-3',
  status: 'pending',
  createdAt: '2024-01-03T00:00:00Z',
  updatedAt: '2024-01-03T00:00:00Z',
} as const;
