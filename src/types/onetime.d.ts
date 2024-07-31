
/**
 * REST API - Backend Ruby app
 *
 **/

// Base interface for common properties
export interface BaseApiRecord {
  identifier: string;
  created: string;
  updated: string;
}

// Define the cust model
export interface Cust extends BaseApiRecord {
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
export interface Plan extends BaseApiRecord {
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

export interface CustomDomain extends BaseApiRecord {
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
  vhost?: string;
}

export interface CustomDomainCluster extends BaseApiRecord {
  created?: string;
  updated?: string;
  identifier?: string;
  cluster_name: string;
  cluster_ip: string;
  type: string;
}

export interface ApiKey extends BaseApiRecord {
  apikey: string;
  active: boolean;
}

export interface BaseApiResponse {
  success: boolean;
}

export interface ApiErrorResponse<T extends BaseApiRecord> extends BaseApiResponse {
  message: string;
  code?: number;
  record?: T | null;
  details?: { [key: string]: never };
}

export interface ApiRecordsResponse<T extends BaseApiRecord> extends BaseApiResponse {
  custid: string;
  records: T[];
  count: number;
  details?: { [key: string]: never };
}

export interface ApiRecordResponse<T extends BaseApiRecord> extends BaseApiResponse {
  record: T;
  details?: { [key: string]: never };
}

export type ApiKeyApiResponse = ApiRecordResponse<ApiKey>;
export type CustomDomainApiResponse = ApiRecordResponse<CustomDomain>;

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
  onSuccess?: (data: ApiRecordsResponse | ApiRecordResponse) => void | Promise<void>;
  onError?: (data: ApiErrorResponse) => void | Promise<void>;
  handleShrimp?: (shrimp: string) => void | Promise<void>
};
