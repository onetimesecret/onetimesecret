
import type { BaseApiRecord, DetailsType } from '../api/responses';

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
