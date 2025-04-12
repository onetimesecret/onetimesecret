// tests/unit/vue/fixtures/types.ts

import { Secret, SecretDetails } from '@/schemas/models/secret';

export interface MockSecretResponse {
  success: boolean;
  record: Secret;
  details: SecretDetails;
}
