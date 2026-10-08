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
  EU: { collection: 'ots', name: 'earth-european-union' },
  US: { collection: 'ots', name: 'earth-united-states' },
  CA: { collection: 'ots', name: 'earth-canada' },
  UK: { collection: 'ots', name: 'earth-united-kingdom' },
  NZ: { collection: 'ots', name: 'earth-new-zealand' },
  BR: { collection: 'ots', name: 'earth-brazil' },
  MX: { collection: 'ots', name: 'earth-mexico' },
  AU: { collection: 'ots', name: 'earth-australia' },
  JP: { collection: 'ots', name: 'earth-japan' },
  SG: { collection: 'ots', name: 'earth-singapore' },
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
