// src/schemas/contracts/config/section/ui.ts

/**
 * User Interface Configuration Schema
 *
 * Maps to the `site.interface:` section in config.defaults.yaml
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults belong in `shapes/config/section/ui.ts`.
 */

import { z } from 'zod';
import { nullableString } from '../shared/primitives';

/**
 * Logo configuration
 */
const userInterfaceLogoSchema = z.object({
  url: z.string().optional(),
  alt: z.string().optional(),
  href: z.string().optional(),
  show_name: z.boolean().optional(),
  prominent: z.boolean().optional(),
});

/**
 * Header branding configuration
 */
const userInterfaceHeaderBrandingSchema = z.object({
  logo: userInterfaceLogoSchema.optional(),
  site_name: z.string().optional(),
});

/**
 * Header navigation configuration
 */
const userInterfaceHeaderNavigationSchema = z.object({
  enabled: z.boolean().optional(),
});

/**
 * Public-facing links surfaced on the homepage when the secret form is
 * gated by auth (e.g. mode=external). Recipients arriving via a shared
 * link use these to learn about the service.
 *
 * Each field is nullable — when null/empty the corresponding affordance
 * is hidden rather than rendered with a broken target.
 */
const userInterfaceHomepagePublicLinksSchema = z.object({
  recipient_intro: nullableString,
});

/**
 * Homepage mode configuration (CIDR-based or header-based)
 */
const userInterfaceHomepageSchema = z.object({
  mode: z.string().nullable().optional(),
  matching_cidrs: z.array(z.string()).optional(),
  mode_header: z.string().optional(),
  public_links: userInterfaceHomepagePublicLinksSchema.optional(),
});

/**
 * Header configuration
 */
const userInterfaceHeaderSchema = z.object({
  enabled: z.boolean().optional(),
  branding: userInterfaceHeaderBrandingSchema.optional(),
  navigation: userInterfaceHeaderNavigationSchema.optional(),
});

/**
 * Footer link item
 */
const userInterfaceFooterLinkSchema = z.object({
  text: z.string().optional(),
  i18n_key: z.string().optional(),
  url: nullableString,
});

/**
 * Footer link group
 */
const userInterfaceFooterGroupSchema = z.object({
  name: z.string().optional(),
  i18n_key: z.string().optional(),
  links: z.array(userInterfaceFooterLinkSchema).optional(),
});

/**
 * Footer links configuration
 */
const userInterfaceFooterLinksSchema = z.object({
  enabled: z.boolean().optional(),
  groups: z.array(userInterfaceFooterGroupSchema).optional(),
});

/**
 * Workspace links configuration (authenticated users only)
 */
const userInterfaceWorkspaceLinksSchema = z.object({
  enabled: z.boolean().optional(),
  links: z.array(userInterfaceFooterLinkSchema).optional(),
});

/**
 * UI capabilities configuration
 */
const uiCapabilitiesSchema = z.object({
  burn: z.boolean().optional(),
  show: z.boolean().optional(),
  receipt: z.boolean().optional(),
  recipient: z.boolean().optional(),
});

/**
 * UI help configuration
 */
const uiHelpSchema = z.object({
  enabled: z.boolean().optional(),
});

const uiSchema = z.object({
  enabled: z.boolean().optional(),
  homepage: userInterfaceHomepageSchema.optional(),
  header: userInterfaceHeaderSchema.optional(),
  footer_links: userInterfaceFooterLinksSchema.optional(),
  workspace_links: userInterfaceWorkspaceLinksSchema.optional(),
  capabilities: uiCapabilitiesSchema.optional(),
  help: uiHelpSchema.optional(),
});

/**
 * API configuration schema
 */
const apiSchema = z.object({
  enabled: z.boolean().optional(),
});

/**
 * Combined interface schema (ui + api)
 */
const userInterfaceSchema = z.object({
  ui: uiSchema.optional(),
  api: apiSchema.optional(),
});

export {
  userInterfaceSchema,
  uiSchema,
  apiSchema,
  userInterfaceLogoSchema,
  userInterfaceHeaderSchema,
  userInterfaceFooterLinksSchema,
  userInterfaceHomepageSchema,
  uiCapabilitiesSchema,
  uiHelpSchema,
};
