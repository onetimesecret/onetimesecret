// src/schemas/shapes/config/section/ui.ts

/**
 * User Interface Configuration Shape
 *
 * Adds runtime defaults on top of the type-only UI contract — header,
 * footer, workspace links, homepage routing, and API toggle defaults.
 *
 * @see src/schemas/contracts/config/section/ui.ts
 */

import { z } from 'zod';
import { nullableString } from '@/schemas/contracts/config/shared/primitives';

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
} from '@/schemas/contracts/config/section/ui';

const userInterfaceLogoShape = z.object({
  url: z.string().optional(),
  alt: z.string().optional(),
  href: z.string().optional(),
  show_name: z.boolean().optional(),
  prominent: z.boolean().optional(),
});

const userInterfaceHeaderBrandingShape = z.object({
  logo: userInterfaceLogoShape.optional(),
  site_name: z.string().optional(),
});

const userInterfaceHeaderNavigationShape = z.object({
  enabled: z.boolean().optional(),
});

const userInterfaceHomepageShape = z.object({
  mode: z.string().nullable().optional(),
  matching_cidrs: z.array(z.string()).default([]),
  mode_header: z.string().default('O-Homepage-Mode'),
});

const userInterfaceHeaderShape = z.object({
  enabled: z.boolean().default(true),
  branding: userInterfaceHeaderBrandingShape.optional(),
  navigation: userInterfaceHeaderNavigationShape.optional(),
});

const userInterfaceFooterLinkShape = z.object({
  text: z.string().optional(),
  i18n_key: z.string().optional(),
  url: nullableString,
});

const userInterfaceFooterGroupShape = z.object({
  name: z.string().optional(),
  i18n_key: z.string().optional(),
  links: z.array(userInterfaceFooterLinkShape).optional(),
});

const userInterfaceFooterLinksShape = z.object({
  enabled: z.boolean().default(false),
  groups: z.array(userInterfaceFooterGroupShape).optional(),
});

const userInterfaceWorkspaceLinksShape = z.object({
  enabled: z.boolean().default(false),
  links: z.array(userInterfaceFooterLinkShape).default([]),
});

const uiCapabilitiesShape = z.object({
  burn: z.boolean().optional(),
  show: z.boolean().optional(),
  receipt: z.boolean().optional(),
  recipient: z.boolean().optional(),
});

const uiHelpShape = z.object({
  enabled: z.boolean().optional(),
});

const uiShape = z.object({
  enabled: z.boolean().default(true),
  homepage: userInterfaceHomepageShape.optional(),
  header: userInterfaceHeaderShape.optional(),
  footer_links: userInterfaceFooterLinksShape.optional(),
  workspace_links: userInterfaceWorkspaceLinksShape.optional(),
  capabilities: uiCapabilitiesShape.optional(),
  help: uiHelpShape.optional(),
});

const apiShape = z.object({
  enabled: z.boolean().default(true),
});

const userInterfaceShape = z.object({
  ui: uiShape.optional(),
  api: apiShape.optional(),
});

export {
  userInterfaceShape,
  uiShape,
  apiShape,
  userInterfaceLogoShape,
  userInterfaceHeaderShape,
  userInterfaceFooterLinksShape,
  userInterfaceHomepageShape,
  uiCapabilitiesShape,
  uiHelpShape,
};
