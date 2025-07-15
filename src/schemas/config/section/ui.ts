// src/schemas/config/section/ui.ts

import { z } from 'zod/v4';
import { nullableString } from '../shared/primitives';

const userInterfaceLogoSchema = z.object({
  url: z.string().optional(),
  alt: z.string().optional(),
  href: z.string().optional(), // Changed from link_to, matches YAML
});

const userInterfaceHeaderBrandingSchema = z.object({
  logo: userInterfaceLogoSchema.optional(),
  site_name: z.string().optional(),
});

const userInterfaceHeaderNavigationSchema = z.object({
  // Adjusted based on YAML <%= ... != 'false' %>
  enabled: z.boolean().optional(),
});

const userInterfaceHeaderSchema = z.object({
  enabled: z.boolean().optional(),
  branding: userInterfaceHeaderBrandingSchema.optional(),
  navigation: userInterfaceHeaderNavigationSchema.optional(),
});

const userInterfaceFooterLinkSchema = z.object({
  text: z.string().optional(),
  i18n_key: z.string().optional(),
  url: nullableString, // Can be nil from ENV
  external: z.boolean().optional(),
  icon: z.string().optional(), // Added
});

const userInterfaceFooterGroupSchema = z.object({
  // YAML :name:
  name: z.string().optional(),
  i18n_key: z.string().optional(),
  links: z.array(userInterfaceFooterLinkSchema).optional(),
});

const userInterfaceFooterLinksSchema = z.object({
  enabled: z.boolean().optional(),
  groups: z.array(userInterfaceFooterGroupSchema).optional(),
});

const userInterfaceSchema = z.object({
  enabled: z.boolean().optional(),
  header: userInterfaceHeaderSchema.optional(),
  footer_links: userInterfaceFooterLinksSchema.optional(),
  signup: z.boolean().optional(), // Added
  signin: z.boolean().optional(), // Added
});

export { userInterfaceSchema };
