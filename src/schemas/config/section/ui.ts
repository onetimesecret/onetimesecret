// src/schemas/config/section/ui.ts

/**
 * User Interface Configuration Schema
 *
 * Maps to the `site.interface:` section in config.defaults.yaml
 */

import { z } from 'zod/v4';
import { nullableString } from '../shared/primitives';

/**
 * Logo configuration
 */
const userInterfaceLogoSchema = z.object({
  url: z.string().optional(),
  alt: z.string().optional(),
  href: z.string().optional(),
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
 * Homepage mode configuration (CIDR-based or header-based)
 */
const userInterfaceHomepageSchema = z.object({
  mode: z.string().nullable().optional(),
  matching_cidrs: z.array(z.string()).default([]),
  mode_header: z.string().default('O-Homepage-Mode'),
  trusted_proxy_depth: z.number().int().nonnegative().default(1),
  trusted_ip_header: z.string().default('X-Forwarded-For'),
});

/**
 * Header configuration
 */
const userInterfaceHeaderSchema = z.object({
  enabled: z.boolean().default(true),
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
  external: z.boolean().optional(),
  icon: z.string().optional(),
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
  enabled: z.boolean().default(false),
  groups: z.array(userInterfaceFooterGroupSchema).optional(),
});

/**
 * UI configuration schema
 */
const uiSchema = z.object({
  enabled: z.boolean().default(true),
  homepage: userInterfaceHomepageSchema.optional(),
  header: userInterfaceHeaderSchema.optional(),
  footer_links: userInterfaceFooterLinksSchema.optional(),
});

/**
 * API configuration schema
 */
const apiSchema = z.object({
  enabled: z.boolean().default(true),
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
};
