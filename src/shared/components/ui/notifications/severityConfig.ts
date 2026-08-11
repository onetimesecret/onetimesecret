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
// (see useBrandTheme) — so brand-tinted severities not only shift color per
// customer, they collapse toward each other, error (brand) and warning
// (branddim) differing only in lightness. Before #4012 that also put `info` on
// the orange brandcomp-* accent, which made neutral notices (e.g. Rodauth's
// "You have been logged in" flash after SSO) read as warnings.
//
// `loading` is the deliberate exception and stays on brand tokens: it reports
// progress, not status, and its spinner already carries that meaning, so
// tinting it per-domain is cohesion rather than mixed signals.

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
    bgClasses: 'bg-brandcompdim-950/95 dark:bg-brandcompdim-50/95',
    textClasses: 'text-brandcompdim-100 dark:text-brandcompdim-700',
    iconClasses: 'text-brandcompdim-300 dark:text-brandcompdim-600',
    ringClasses: 'ring-brandcompdim-700/50 dark:ring-brandcompdim-300/50',
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
    bgClasses: 'bg-brandcompdim-50/95 dark:bg-brandcompdim-950/95',
    textClasses: 'text-brandcompdim-700 dark:text-brandcompdim-100',
    iconClasses: 'text-brandcompdim-600 dark:text-brandcompdim-300',
    ringClasses: 'ring-brandcompdim-200/50 dark:ring-brandcompdim-800/50',
  },
};

// Banner uses /90 opacity instead of /95 — override at the bg level only.
// Everything else (text, icon, ring) matches standard.
//
// These bg classes are written as explicit literals (not a runtime transform
// of STANDARD_COLORS) because Tailwind v4 scans source text for class names:
// a value like `bg-green-50/90` must appear verbatim in a file or its utility
// is never generated.
const BANNER_COLORS: Record<string, SeverityColors> = {
  success: {
    ...STANDARD_COLORS.success,
    bgClasses: 'bg-green-50/90 dark:bg-green-950/90',
  },
  error: {
    ...STANDARD_COLORS.error,
    bgClasses: 'bg-red-50/90 dark:bg-red-950/90',
  },
  warning: {
    ...STANDARD_COLORS.warning,
    bgClasses: 'bg-amber-50/90 dark:bg-amber-950/90',
  },
  info: {
    ...STANDARD_COLORS.info,
    bgClasses: 'bg-sky-50/90 dark:bg-sky-950/90',
  },
  loading: {
    ...STANDARD_COLORS.loading,
    bgClasses: 'bg-brandcompdim-50/90 dark:bg-brandcompdim-950/90',
  },
};

const DEFAULT_COLORS: SeverityColors = STANDARD_COLORS.info;

export function getSeverityMeta(severity: string | null): SeverityMeta {
  return SEVERITY_META[severity || 'info'] ?? SEVERITY_META.info;
}

export function getInvertedColors(severity: string | null): SeverityColors {
  return INVERTED_COLORS[severity || 'info'] ?? DEFAULT_COLORS;
}

export function getStandardColors(severity: string | null): SeverityColors {
  return STANDARD_COLORS[severity || 'info'] ?? DEFAULT_COLORS;
}

export function getBannerColors(severity: string | null): SeverityColors {
  return BANNER_COLORS[severity || 'info'] ?? DEFAULT_COLORS;
}
