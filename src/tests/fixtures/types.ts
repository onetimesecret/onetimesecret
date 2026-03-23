// src/tests/fixtures/types.ts

import { Secret, SecretDetails } from '@/schemas/shapes/v2/secret';

export interface MockSecretResponse {
  success: boolean;
  record: Secret;
  details: SecretDetails;
}
