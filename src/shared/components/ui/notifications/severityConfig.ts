// src/shared/components/ui/notifications/severityConfig.ts
//
// Severity → icon, pulse, and color mappings shared by global notification visuals.
//
// Two color palettes exist because NotificationPill uses an inverted scheme
// (dark bg in light mode) while Card/Banner use a standard scheme (light bg
// in light mode). Both are exposed here so visuals don't duplicate the tables.
//
// The four STATUS severities use fixed semantic hues — success/green,
// error/red, warning/amber, info/sky — rather than the --color-brand*
// families. Status is a claim about what happened, so it has to be legible
// independent of who is looking: a red toast means "this failed" on every
// domain. Brand tokens can't carry that, because generateBrandPalette derives
// brand, branddim, brandcomp and brandcompdim from a single per-domain hue
// (see useBrandTheme) — so brand-tinted severities shift color per customer
// and collapse toward each other: branddim is brand at reduced chroma and
// mid-range lightness, and every scale clamps to the same near-black floor at
// shade 950, where the old error (brand) and warning (branddim) pill
// backgrounds were literally identical. Before #4012 `info` sat on
// brandcomp-* — the complement of the domain hue, orange on the default blue
// palette — which made neutral notices (e.g. Rodauth's "You have been logged
// in" flash after SSO) read as warnings.
//
// `loading` reports progress, not status, so it takes no semantic hue — but
// it avoids brand tokens too: brandcompdim is the complement of the domain
// hue, which on branded domains can land next to the amber/sky reserved for
// warning/info. Neutral gray carries "in progress" on every domain.

export interface SeverityMeta {
  icon: string;
  pulse: boolean;
  spinIcon: boolean;
}

export interface SeverityColors {
  bgClasses: string;
  textClasses: string;
  iconClasses: string;
  ringClasses?: string;
}

const SEVERITY_META: Record<string, SeverityMeta> = {
  success: { icon: 'check-circle', pulse: true, spinIcon: false },
  error: { icon: 'alert-circle', pulse: false, spinIcon: false },
  warning: { icon: 'alert', pulse: false, spinIcon: false },
  info: { icon: 'information', pulse: true, spinIcon: false },
  loading: { icon: 'loading', pulse: false, spinIcon: true },
};

// Inverted palette: dark bg in light mode, light bg in dark mode.
// Used by NotificationPill.
const INVERTED_COLORS: Record<string, SeverityColors> = {
  success: {
    bgClasses: 'bg-green-950/95 dark:bg-green-50/95',
    textClasses: 'text-green-100 dark:text-green-700',
    iconClasses: 'text-green-300 dark:text-green-600',
    ringClasses: 'ring-green-700/50 dark:ring-green-300/50',
  },
  error: {
    bgClasses: 'bg-red-950/95 dark:bg-red-50/95',
    textClasses: 'text-red-100 dark:text-red-700',
    iconClasses: 'text-red-300 dark:text-red-600',
    ringClasses: 'ring-red-700/50 dark:ring-red-300/50',
  },
  warning: {
    bgClasses: 'bg-amber-950/95 dark:bg-amber-50/95',
    textClasses: 'text-amber-100 dark:text-amber-700',
    iconClasses: 'text-amber-300 dark:text-amber-600',
    ringClasses: 'ring-amber-700/50 dark:ring-amber-300/50',
  },
  info: {
    bgClasses: 'bg-sky-950/95 dark:bg-sky-50/95',
    textClasses: 'text-sky-100 dark:text-sky-700',
    iconClasses: 'text-sky-300 dark:text-sky-600',
    ringClasses: 'ring-sky-700/50 dark:ring-sky-300/50',
  },
  loading: {
    bgClasses: 'bg-gray-950/95 dark:bg-gray-50/95',
    textClasses: 'text-gray-100 dark:text-gray-700',
    iconClasses: 'text-gray-300 dark:text-gray-600',
    ringClasses: 'ring-gray-700/50 dark:ring-gray-300/50',
  },
};

// Standard palette: light bg in light mode, dark bg in dark mode.
// Used by NotificationCard and NotificationBanner.
const STANDARD_COLORS: Record<string, SeverityColors> = {
  success: {
    bgClasses: 'bg-green-50/95 dark:bg-green-950/95',
    textClasses: 'text-green-700 dark:text-green-100',
    iconClasses: 'text-green-600 dark:text-green-300',
    ringClasses: 'ring-green-200/50 dark:ring-green-800/50',
  },
  error: {
    bgClasses: 'bg-red-50/95 dark:bg-red-950/95',
    textClasses: 'text-red-700 dark:text-red-100',
    iconClasses: 'text-red-600 dark:text-red-300',
    ringClasses: 'ring-red-200/50 dark:ring-red-800/50',
  },
  warning: {
    bgClasses: 'bg-amber-50/95 dark:bg-amber-950/95',
    textClasses: 'text-amber-700 dark:text-amber-100',
    iconClasses: 'text-amber-600 dark:text-amber-300',
    ringClasses: 'ring-amber-200/50 dark:ring-amber-800/50',
  },
  info: {
    bgClasses: 'bg-sky-50/95 dark:bg-sky-950/95',
    textClasses: 'text-sky-700 dark:text-sky-100',
    iconClasses: 'text-sky-600 dark:text-sky-300',
    ringClasses: 'ring-sky-200/50 dark:ring-sky-800/50',
  },
  loading: {
    bgClasses: 'bg-gray-50/95 dark:bg-gray-950/95',
    textClasses: 'text-gray-700 dark:text-gray-100',
    iconClasses: 'text-gray-600 dark:text-gray-300',
    ringClasses: 'ring-gray-200/50 dark:ring-gray-800/50',
  },
};

// Banner uses /90 opacity instead of /95, and unlike Card renders no ring —
// entries carry only the fields NotificationBanner consumes.
//
// These bg classes are written as explicit literals (not a runtime transform
// of STANDARD_COLORS) because Tailwind v4 scans source text for class names:
// a value like `bg-green-50/90` must appear verbatim in a file or its utility
// is never generated.
const BANNER_COLORS: Record<string, SeverityColors> = {
  success: {
    bgClasses: 'bg-green-50/90 dark:bg-green-950/90',
    textClasses: STANDARD_COLORS.success.textClasses,
    iconClasses: STANDARD_COLORS.success.iconClasses,
  },
  error: {
    bgClasses: 'bg-red-50/90 dark:bg-red-950/90',
    textClasses: STANDARD_COLORS.error.textClasses,
    iconClasses: STANDARD_COLORS.error.iconClasses,
  },
  warning: {
    bgClasses: 'bg-amber-50/90 dark:bg-amber-950/90',
    textClasses: STANDARD_COLORS.warning.textClasses,
    iconClasses: STANDARD_COLORS.warning.iconClasses,
  },
  info: {
    bgClasses: 'bg-sky-50/90 dark:bg-sky-950/90',
    textClasses: STANDARD_COLORS.info.textClasses,
    iconClasses: STANDARD_COLORS.info.iconClasses,
  },
  loading: {
    bgClasses: 'bg-gray-50/90 dark:bg-gray-950/90',
    textClasses: STANDARD_COLORS.loading.textClasses,
    iconClasses: STANDARD_COLORS.loading.iconClasses,
  },
};

export function getSeverityMeta(severity: string | null): SeverityMeta {
  return SEVERITY_META[severity || 'info'] ?? SEVERITY_META.info;
}

export function getInvertedColors(severity: string | null): SeverityColors {
  return INVERTED_COLORS[severity || 'info'] ?? INVERTED_COLORS.info;
}

export function getStandardColors(severity: string | null): SeverityColors {
  return STANDARD_COLORS[severity || 'info'] ?? STANDARD_COLORS.info;
}

export function getBannerColors(severity: string | null): SeverityColors {
  return BANNER_COLORS[severity || 'info'] ?? BANNER_COLORS.info;
}
