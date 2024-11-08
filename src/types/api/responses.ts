import type { CustomDomain, MetadataData, SecretData, ConcealData, CheckAuthData, BrandSettings, ImageProps } from '../declarations/index';

export interface BaseApiResponse {
  success: boolean;
}


// Base interface for common properties
export interface BaseApiRecord {
  identifier: string;
  created: string;
  updated: string;
}

export type DetailsType = ApiRecordResponse<BaseApiRecord>['details'];

export interface ApiErrorResponse<T extends BaseApiRecord> extends BaseApiResponse {
  message: string;
  code?: number;
  record?: T | null;
  details?: DetailsType;
}

export interface ApiRecordsResponse<T extends BaseApiRecord> extends BaseApiResponse {
  custid: string;
  records: T[];
  count: number;
  details?: DetailsType;
}

export interface ApiRecordResponse<T extends BaseApiRecord> extends BaseApiResponse {
  record: T;
  details?: DetailsType;
}

export interface AsyncDataResult<T> {
  data: T | null;
  error: Error | string | null;
  status: number | null;
}


export interface ApiToken extends BaseApiRecord {
  apitoken: string;
  active: boolean;
}

export interface Account extends BaseApiRecord {
  cust: Customer;
  apitoken?: string;
  stripe_customer: Stripe.Customer;
  stripe_subscriptions: Stripe.Subscription[];
}


export type ApiTokenApiResponse = ApiRecordResponse<ApiToken>;
export type CustomDomainApiResponse = ApiRecordResponse<CustomDomain>;
export type AccountApiResponse = ApiRecordResponse<Account>;
export type ColonelDataApiResponse = ApiRecordResponse<ColonelData>;
export type MetadataDataApiResponse = ApiRecordResponse<MetadataData>;
export type SecretDataApiResponse = ApiRecordResponse<SecretData>;
export type ConcealDataApiResponse = ApiRecordResponse<ConcealData>;
export type CheckAuthDataApiResponse = ApiRecordResponse<CheckAuthData>;
export type BrandSettingsApiResponse = ApiRecordResponse<BrandSettings>;
export type ImagePropsApiResponse = ApiRecordResponse<ImageProps>;
export type CustomDomainRecordsApiResponse = ApiRecordsResponse<CustomDomain>;
