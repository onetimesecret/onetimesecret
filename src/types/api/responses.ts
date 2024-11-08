import type { BaseApiRecord } from '../index';
import type { ApiToken, CustomDomain, Account, ColonelData, MetadataData, SecretData, ConcealData, CheckAuthData, BrandSettings, ImageProps } from '../index';

export interface BaseApiResponse {
  success: boolean;
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
