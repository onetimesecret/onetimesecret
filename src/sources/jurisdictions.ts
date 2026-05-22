// src/sources/jurisdictions.ts
//
// Static jurisdiction metadata for icon display.
// Identifiers and domains come from config (ENV/YAML).
// Display names come from i18n keys: web.regions.jurisdictions.{id}.name

/**
 * Icon configuration for jurisdiction display.
 * Matches JurisdictionIcon type from schemas/contracts/config/section/jurisdiction.ts
 */
export interface JurisdictionIconConfig {
  collection: string;
  name: string;
}

/**
 * Default icon definitions for known jurisdiction identifiers.
 * Used when jurisdiction config doesn't include icon data.
 */
export const JURISDICTION_ICONS: Record<string, JurisdictionIconConfig> = {
  EU: { collection: 'fa6-solid', name: 'earth-europe' },
  US: { collection: 'fa6-solid', name: 'earth-americas' },
  CA: { collection: 'fa6-solid', name: 'earth-americas' },
  UK: { collection: 'fa6-solid', name: 'earth-europe' },
  NZ: { collection: 'fa6-solid', name: 'earth-oceania' },
  AT: { collection: 'fa6-solid', name: 'earth-europe' },
  APAC: { collection: 'fa6-solid', name: 'earth-asia' },
};

export const DEFAULT_JURISDICTION_ICON: JurisdictionIconConfig = {
  collection: 'fa6-solid',
  name: 'globe',
};

/**
 * Get the icon for a jurisdiction identifier.
 * Falls back to default globe icon if no mapping exists.
 */
export function getJurisdictionIcon(identifier: string): JurisdictionIconConfig {
  return JURISDICTION_ICONS[identifier.toUpperCase()] ?? DEFAULT_JURISDICTION_ICON;
}
