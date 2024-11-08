import type { BaseApiRecord } from './index';
import type { Plan } from './index';

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

  feature_flags?: { [key: string]: boolean | number | string };
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

  feature_flags?: { [key: string]: boolean | number | string };
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

export interface Plan extends BaseApiRecord {
  planid: string;
  price: number;
  discount: number;
  options: PlanOptions;
}

export interface AvailablePlans {
  [key: string]: Plan;
}
