
/**
 * REST API - Backend Ruby app
 *
 **/

import type Stripe from 'stripe';


// Base interface for common properties
export interface BaseApiRecord {
  identifier: string;
  created: string;
  updated: string;
}

// Define the customer model
export interface Cust extends BaseApiRecord {
  custid: string;
  role: string;
  planid?: string;
  plan: Plan;
  verified: string;
  updated: number;
  created: number;
  secrets_created: number;
  active: string;

  stripe_checkout_email?: string;
  stripe_subscription_id?: string;
  stripe_customer_id?: string;
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
    name: string;
    cname?: boolean;
    private?: boolean;
    email?: boolean;
  };
}

// Define the interface for the authentication settings object
interface AuthenticationSettings {
  enabled: boolean;
  signup: boolean;
  signin: boolean;
  autoverify: boolean;
}

export interface ApproximatedVHost {
  apx_hit: boolean;
  created_at: string;
  dns_pointed_at: string;
  has_ssl: boolean;
  id: number;
  incoming_address: string;
  is_resolving: boolean;
  keep_host: string | null;
  last_monitored_humanized: string;
  last_monitored_unix: number;
  ssl_active_from: string;
  ssl_active_until: string;
  status: string;
  status_message: string;
  target_address: string;
  target_ports: string;
  user_message: string;
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
  vhost?: ApproximatedVHost;
}

export interface CustomDomainCluster extends BaseApiRecord {
  created?: string;
  updated?: string;
  identifier?: string;
  type: string;
  cluster_ip: string;
  cluster_name: string;
  vhost_target: string;
}

export interface ApiToken extends BaseApiRecord {
  apitoken: string;
  active: boolean;
}

export interface Account extends BaseApiRecord {
  cust: Cust;
  apitoken?: string;
  stripe_customer: Stripe.Customer;
  stripe_subscriptions: Stripe.Subscription[];
}

export interface ColonelData extends BaseApiRecord {
  recent_customers: Cust[];
  today_feedback: Feedback[];
  yesterday_feedback: Feedback[];
  older_feedback: Feedback[];
  redis_info: string;
  plans_enabled: boolean;
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
  };
}

export interface Feedback {
  msg: string;
  stamp: string;
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

export type ApiTokenApiResponse = ApiRecordResponse<ApiToken>;
export type CustomDomainApiResponse = ApiRecordResponse<CustomDomain>;
export type AccountApiResponse = ApiRecordResponse<Account>;
export type ColonelDataApiResponse = ApiRecordResponse<ColonelData>;

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

export interface DashboardMetadata extends BaseApiRecord {
  // Extra keys added to Metadata records by Dashboard
  // view. Can be moved to the ts model.
  shortkey: string;
  show_recipients: boolean;
  stamp: string;
  uri: string;
  is_received: boolean;
  is_burned: boolean;
  is_destroyed: boolean;
}

export interface Metadata extends DashboardMetadata {
  custid: string;
  state: string;
  secret_key: string;
  secret_shortkey: string;
  secret_ttl: number;
  share_domain: string;
  passphrase: string;
  viewed: boolean;
  received: boolean;
  shared: boolean;
  burned: boolean;
  recipients: string[];
  truncate: boolean;
  key: string;
}

// Secret interface
export interface Secret extends BaseApiRecord {
  custid: string;
  state: string;
  value: string;
  metadata_key: string;
  original_size: number;
  value_checksum: string;
  value_encryption: string;
  lifespan: number;
  share_domain: string;
  verification: string;
  truncated: boolean;
  maxviews: number; // always 1 (here for backwards compat)
}
