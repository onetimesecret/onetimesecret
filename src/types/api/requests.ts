import type { BrandSettings } from '../custom_domains';

export interface UpdateDomainBrandRequest {
  brand: Partial<BrandSettings>;
}

export interface CreateDomainRequest {
  domain: string;
}
