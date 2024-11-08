import type Stripe from 'stripe';
import type { Component } from 'vue';

// Re-export all types
export * from './api/responses';
export * from './brand';
export * from './customer';
export * from './custom_domain';
export * from './metadata';
export * from './secret';

// Base interface for common properties
export interface BaseApiRecord {
  identifier: string;
  created: string;
  updated: string;
}

export interface ImageProps {
  encoded: string;
  content_type: string;
  filename: string;
  bytes?: number;
  width?: number;
  height?: number;
  ratio?: number;
}

export interface SecretOptions {
  // Default Time-To-Live (TTL) for secrets in seconds
  default_ttl: number; // Default: 604800 (7 days in seconds)

  // Available TTL options for secret creation (in seconds)
  // These options will be presented to users when they create a new secret
  // Format: Array of integers representing seconds
  ttl_options: number[]; // Default: [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600]
}

export interface AuthenticationSettings {
  enabled: boolean;
  signup: boolean;
  signin: boolean;
  autoverify: boolean;
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
  current_jurisdiction: string;
  jurisdictions: Jurisdiction[];
}

export interface AsyncDataResult<T> {
  data: T | null;
  error: Error | string | null;
  status: number | null;
}

export interface LayoutProps {
  displayMasthead?: boolean;
  displayNavigation?: boolean;
  displayLinks?: boolean;
  displayFeedback?: boolean;
  displayVersion?: boolean;
  displayPoweredBy?: boolean;
  displayToggles?: boolean;
}

export type FormSubmissionOptions = {
  url?: string;
  successMessage: string;
  redirectUrl?: string;
  redirectDelay?: number;
  getFormData?: () => FormData | URLSearchParams;
  onSuccess?: (data: unknown) => void | Promise<void>;
  onError?: (data: unknown) => void | Promise<void>;
};

// Modify the Vue Router module augmentation
import 'vue-router';

declare module 'vue-router' {
  interface RouteMeta {
    requiresAuth?: boolean;
    layout?: Component;
    layoutProps?: LayoutProps;
    initialData?: AsyncDataResult<unknown>;
  }
}
