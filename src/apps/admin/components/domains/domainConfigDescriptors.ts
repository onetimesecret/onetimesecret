// src/apps/admin/components/domains/domainConfigDescriptors.ts

import type { EditableDomainConfigKind } from '@/schemas/api/internal/responses/colonel-domain-configs';

/**
 * Field descriptors driving {@link DomainConfigEditModal}'s per-kind form.
 *
 * Field names and enum values mirror the colonel upsert contract EXACTLY
 * (`PUT /api/colonel/domains/:extid/configs/:kind` writable fields); the
 * server is authoritative and re-validates. `defaultValue` mirrors the model
 * defaults used when creating a missing record (everything disabled /
 * passthrough / create — behavior-neutral).
 */
export interface DomainConfigFieldDescriptor {
  /** Serialized field name — matches the API's writable field verbatim. */
  name: string;
  /** Which control the modal renders. `domains` = one-domain-per-line textarea. */
  type: 'boolean' | 'select' | 'domains';
  /** Select options (the server-side enum values). */
  options?: readonly string[];
  /** When true the select offers an "unset" choice that maps to null. */
  allowUnset?: boolean;
  /** Value used when creating a missing record (model default). */
  defaultValue: boolean | string | string[] | null;
}

/** Writable fields per editable kind, in display order. */
export const DOMAIN_CONFIG_EDIT_FIELDS: Record<
  EditableDomainConfigKind,
  readonly DomainConfigFieldDescriptor[]
> = {
  signin: [
    { name: 'enabled', type: 'boolean', defaultValue: false },
    { name: 'signin_enabled', type: 'boolean', defaultValue: false },
    { name: 'email_auth_enabled', type: 'boolean', defaultValue: false },
    { name: 'sso_enabled', type: 'boolean', defaultValue: false },
    {
      name: 'restrict_to',
      type: 'select',
      options: ['password', 'email_auth', 'webauthn', 'sso'],
      allowUnset: true,
      defaultValue: null,
    },
  ],
  signup: [
    { name: 'enabled', type: 'boolean', defaultValue: false },
    { name: 'signup_enabled', type: 'boolean', defaultValue: false },
    { name: 'autoverify', type: 'boolean', defaultValue: false },
    {
      name: 'validation_strategy',
      type: 'select',
      options: ['passthrough', 'domain_allowlist', 'mx', 'smtp'],
      defaultValue: 'passthrough',
    },
    { name: 'allowed_signup_domains', type: 'domains', defaultValue: [] },
  ],
  homepage: [
    { name: 'enabled', type: 'boolean', defaultValue: false },
    {
      name: 'secrets_mode',
      type: 'select',
      options: ['create', 'incoming'],
      defaultValue: 'create',
    },
    {
      name: 'disabled_homepage_variant',
      type: 'select',
      options: ['v1', 'minimal', 'closed'],
      allowUnset: true,
      defaultValue: null,
    },
  ],
  api: [{ name: 'enabled', type: 'boolean', defaultValue: false }],
  // Recipients stay workspace-managed in v1 — `enabled` is the only writable field.
  incoming: [{ name: 'enabled', type: 'boolean', defaultValue: false }],
};
