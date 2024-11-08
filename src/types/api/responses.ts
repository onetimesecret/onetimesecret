import { Stripe } from 'stripe';
import type { Customer, Feedback, MetadataData, SecretData, ConcealData } from '@/types/core';
import type { CustomDomain, BrandSettings, ImageProps } from '@/types/custom_domains';

export interface BaseApiResponse {
  success: boolean;
}

export interface CheckAuthData extends BaseApiResponse {
  record: Customer;
  details: {
    authenticated: boolean;
  }
}

export interface ApiClient {
  get<T>(url: string): Promise<BaseApiResponse & { data: T }>;
  post<T>(url: string, data: unknown): Promise<BaseApiResponse & { data: T }>;
  put<T>(url: string, data: unknown): Promise<BaseApiResponse & { data: T }>;
  delete<T>(url: string): Promise<BaseApiResponse & { data: T }>;
}

// Base interface for common properties
export interface BaseApiRecord {
  identifier: string;
  // Update to use Date objects instead of strings
  created: Date;
  updated: Date;
}

export type DetailsType = {
  [key: string]: string | number | boolean | null | object;
};

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

export interface ColonelData extends BaseApiRecord {
  apitoken: string;
  active?: boolean;
  recent_customers: Customer[];
  today_feedback: Feedback[];
  yesterday_feedback: Feedback[];
  older_feedback: Feedback[];
  redis_info: number;
  plans_enabled: number;
  counts: {
    session_count: number;
    customer_count: number;
    recent_customer_count: number;
    metadata_count: number;
    secret_count: number;
    secrets_created: number;
    secrets_shared: number;
    emails_sent: number;
    feedback_count: number;
    today_feedback_count: number;
    yesterday_feedback_count: number;
    older_feedback_count: number;
  }
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
export type UpdateDomainBrandResponse = ApiRecordResponse<CustomDomain>;
