// src/schemas/shapes/config/section/ui.ts

/**
 * User Interface Configuration Shape
 *
 * Adds runtime defaults on top of the type-only UI contract — header,
 * footer, workspace links, homepage routing, and API toggle defaults.
 *
 * @see src/schemas/contracts/config/section/ui.ts
 */

import {
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
import { augment, type AugmentTree } from '@/schemas/utils/augment';

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

const userInterfaceLogoShape = userInterfaceLogoSchema;

const homepageTree: AugmentTree = {
  matching_cidrs: (a) => a.default([]),
  mode_header: (s) => s.default('O-Homepage-Mode'),
};

const headerTree: AugmentTree = {
  enabled: (b) => b.default(true),
};

const footerLinksTree: AugmentTree = {
  enabled: (b) => b.default(false),
};

const userInterfaceHomepageShape = augment(userInterfaceHomepageSchema, homepageTree);
const userInterfaceHeaderShape = augment(userInterfaceHeaderSchema, headerTree);
const userInterfaceFooterLinksShape = augment(userInterfaceFooterLinksSchema, footerLinksTree);
const uiCapabilitiesShape = uiCapabilitiesSchema;
const uiHelpShape = uiHelpSchema;

const uiShape = augment(uiSchema, {
  enabled: (b) => b.default(true),
  homepage: homepageTree,
  header: headerTree,
  footer_links: footerLinksTree,
  workspace_links: { enabled: (b) => b.default(false) },
});

const apiShape = augment(apiSchema, {
  enabled: (b) => b.default(true),
});

const userInterfaceShape = augment(userInterfaceSchema, {
  ui: {
    enabled: (b) => b.default(true),
    homepage: homepageTree,
    header: headerTree,
    footer_links: footerLinksTree,
    workspace_links: { enabled: (b) => b.default(false) },
  },
  api: { enabled: (b) => b.default(true) },
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
