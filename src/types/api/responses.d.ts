// src/types/api/responses.ts
import type { CustomDomain } from '../onetime';

export interface UpdateDomainBrandResponse {
  success: boolean;
  domain: CustomDomain;
}
