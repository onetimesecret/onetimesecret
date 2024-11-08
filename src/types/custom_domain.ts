import type { BaseApiRecord } from './index';
import type { BrandSettings, BrokenBrandSettings } from './brand';

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
  brand?: BrandSettings;
  // Images are queried separately
}

export interface BrokenCustomDomain extends BaseApiRecord {
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
  brand?: BrokenBrandSettings;
  // Images are queried separately
}

export interface CustomDomainCluster extends BaseApiRecord {
  created?: string;
  updated?: string;
  identifier?: string;
  type: string;
  cluster_ip: string;
  cluster_name: string;
  cluster_host: string;
  vhost_target: string;
}

// Define domain strategy types based on the Ruby middleware
export type DomainStrategy = 'canonical' | 'subdomain' | 'custom' | 'invalid';
