import type { BaseApiRecord } from '../api/responses';
import type { MetadataData } from './metadata';

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
  secret_value: string;
  secret?: string;
}

export interface SecretDetails {
  continue: boolean;
  show_secret: boolean;
  correct_passphrase: boolean;
  display_lines: number;
  one_liner: boolean;
}

export interface Secret extends BaseApiRecord {
  custid: string;
  state: string;
  value: string;
  secret_value?: string;
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

export interface ConcealData {
  metadata: MetadataData;
  secret: SecretData;
  share_domain: string;
}

export interface ConcealDetails {
  kind: string;
  recipient: string;
  recipient_safe: string;
}
