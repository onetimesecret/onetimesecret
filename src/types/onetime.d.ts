
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
export interface Customer extends BaseApiRecord {
  custid: string;
  role: string;
  planid?: string;
  plan: Plan;
  verified: string;
  updated: number;
  created: number;
  secrets_created: number;
  active: string;
  locale: string;

  stripe_checkout_email?: string;
  stripe_subscription_id?: string;
  stripe_customer_id?: string;
}

export interface ColonelCustomer {
  custid: string;
  planid?: string;
  colonel: boolean;
  secrets_created: number;
  secrets_shared: number;
  emails_sent: number;
  verified: boolean;
  stamp: string;
}

export interface SecretOptions {
  // Default Time-To-Live (TTL) for secrets in seconds
  default_ttl: number; // Default: 604800 (7 days in seconds)

  // Available TTL options for secret creation (in seconds)
  // These options will be presented to users when they create a new secret
  // Format: Array of integers representing seconds
  ttl_options: number[]; // Default: [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600]
}

export interface PlanOptions {
  ttl: number;
  size: number;
  api: boolean;
  name: string;
  email?: boolean;
  custom_domains?: boolean;
  dark_mode?: boolean;
  cname?: boolean;
  private?: boolean;
}

// Define the plan model
export interface Plan extends BaseApiRecord {
  planid: string;
  price: number;
  discount: number;
  options: PlanOptions;
}

export interface AvailablePlans {
  [key: string]: Plan;
}

// Define the interface for the authentication settings object
export interface AuthenticationSettings {
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
  is_apex: boolean;
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
  cust: Customer;
  apitoken?: string;
  stripe_customer: Stripe.Customer;
  stripe_subscriptions: Stripe.Subscription[];
}

export interface ColonelData extends BaseApiRecord {
  recent_customers: ColonelCustomer[];
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

export interface MetadataData extends BaseApiRecord {
  key: string;
  shortkey: string;
  secret_key: string;
  secret_shortkey: string;
  recipients: string[];
  created_date_utc: string;
  expiration_stamp: string;
  share_path: string;
  burn_path: string;
  metadata_path: string;
  share_url: string;
  metadata_url: string;
  burn_url: string;
  share_domain: string;
}

export interface MetadataDetails extends DetailsType {
  body_class: string;
  burned_date_utc: string;
  burned_date: string;
  can_decrypt: boolean;
  display_feedback: boolean;
  display_lines: number;
  has_maxviews: boolean;
  has_passphrase: boolean;
  is_burned: boolean;
  is_destroyed: boolean;
  is_received: boolean;
  maxviews: number;
  no_cache: boolean;
  received_date_utc: string;
  received_date: string;
  secret_value: string;
  show_metadata_link: boolean;
  show_metadata: boolean;
  show_recipients: boolean;
  show_secret_link: boolean;
  show_secret: boolean;
  title: string;
  is_truncated: boolean;
  view_count: number;
}

export interface SecretData extends BaseApiRecord {

  key: string;
  secret_key: string;
  secret_shortkey: string;
  is_truncated: boolean;
  original_size: number;
  verification: string;
  share_domain: string;
  is_owner: boolean;
  has_passphrase: boolean;
  secret_value?: string;
}

export interface SecretDetails extends DetailsType {
  continue: boolean;
  show_secret: boolean;
  correct_passphrase: boolean;
  display_lines: number;
  one_liner: boolean;
}

export interface ConcealData {
  metadata: MetadataData;
  secret: SecretData;
  share_domain: string;
}

export interface ConcealDetails {
  kind: string,
  recipient: string,
  recipient_safe: string
}

export interface CheckAuthData extends Customer {
  last_login?: number
}

export interface CheckAuthDetails {
  authorized: boolean;
}

export interface Feedback {
  msg: string;
  stamp: string;
}

// Base class with common properties
export class BaseEntity {
  identifier: string;
  display_name: string;
  domain: string;
  icon: string;

  constructor(identifier: string, display_name: string, domain: string, icon: string) {
    this.identifier = identifier;
    this.display_name = display_name;
    this.domain = domain;
    this.icon = icon;
  }
}

// Jurisdiction class extending BaseEntity
export class Jurisdiction extends BaseEntity {
  // Additional properties specific to Jurisdiction can be added here
}

// Region class extending BaseEntity
export class Region extends BaseEntity {
  // Additional properties specific to Region can be added here
}

// Note: "Regions" is not a list of Region objects. It represents the site settings for all regions. A better name would be RegionsConfig.
export interface Regions {
  enabled: boolean;
  current_jurisdiction: str
  jurisdictions: Jurisdiction[];
}

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
  is_truncated: boolean;
  maxviews: number; // always 1 (here for backwards compat)
}
