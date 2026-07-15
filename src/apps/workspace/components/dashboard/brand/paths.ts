// src/apps/workspace/components/dashboard/brand/paths.ts
//
// The three branding paths shown in the editor's path switcher. `available`
// marks whether the path is functional (Simple) or a "coming soon" teaser
// (Match my site, Advanced). The display name/tagline are resolved from i18n in
// the switcher keyed by id (web.branding.path_<id>, web.branding.path_<id>_tag).

export type BrandPath = 'simple' | 'match' | 'advanced';

export interface BrandPathMeta {
  id: BrandPath;
  available: boolean;
}

export const BRAND_PATHS: readonly BrandPathMeta[] = [
  { id: 'simple', available: true },
  { id: 'match', available: false },
  { id: 'advanced', available: false },
] as const;
