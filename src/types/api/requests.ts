import type { BrandSettings } from '../onetime';

export interface UpdateDomainBrandRequest {
  brand: Partial<BrandSettings>;
}

export interface CreateDomainRequest {
  domain: string;
}
