import type { BrandSettings } from '@/schemas/models/domain/brand';

export interface UpdateDomainBrandRequest {
  brand: Partial<BrandSettings>;
}

export interface CreateDomainRequest {
  domain: string;
}

export interface ExceptionReport {
  message: string;
  type: string;
  stack: string;
  url: string;
  line: number;
  column: number;
  environment: string;
  release: string;
}
