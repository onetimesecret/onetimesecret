/* eslint-disable no-unused-vars */

/**
 * REST API - Backend Ruby app
 *
 **/

// Base interface for common properties
export interface BaseResponseRecord {
  identifier: string;
  created: string;
  updated: string;
}

// Define the cust model
export interface Cust extends BaseResponseRecord {
  custid: string;
  role: string;
  planid?: string;
  plan: Plan;
  verified: string;
  updated: string;
  created: string;
  secrets_created: string;
  active: string;
}

// Define the plan model
export interface Plan extends BaseResponseRecord {
  planid: string;
  price: number;
  discount: number;
  options: {
    ttl: number;
    size: number;
    api: boolean;
    cname?: boolean;
    private?: boolean;
    name: string;
  };
}

export interface CustomDomain extends BaseResponseRecord {
  created: string;
  updated: string;
  identifier: string;
  domainid: string;
  custid: string;
  display_domain: string;
  base_domain: string;
  subdomain: string;
  trd: string;
  tld: string;
  sld: string;
  verified: boolean;
  _original_value: string;
  txt_validation_host: string;
  txt_validation_value: string;
}

export type APIRecordsResponse = {
  success: boolean;
  custid: string;
  records: BaseResponseRecord[];
  count: number;
}

export type APIRecordResponse = {
  success: boolean;
  custid: string;
  record: BaseResponseRecord | null;
}

/**
 * Front-end Vue App
 *
 **/
export type FormSubmissionOptions = {
  url?: string;
  successMessage: string;
  redirectUrl?: string;
  redirectDelay?: number;
  getFormData?: () => FormData | URLSearchParams;
  onSuccess?: (data: Record<string, string>) => void | Promise<void>;
  onError?: (data: Record<string, string>) => void | Promise<void>;
  handleShrimp?: (shrimp: string) => void | Promise<void>
};
