// src/shared/components/ui/notifications/severityConfig.ts
//
// Severity → icon, pulse, and color mappings shared by global notification visuals.
//
// Two color palettes exist because NotificationPill uses an inverted scheme
// (dark bg in light mode) while Card/Banner use a standard scheme (light bg
// in light mode). Both are exposed here so visuals don't duplicate the tables.

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
    bgClasses: 'bg-brand-950/95 dark:bg-brand-50/95',
    textClasses: 'text-brand-100 dark:text-brand-700',
    iconClasses: 'text-brand-300 dark:text-brand-600',
    ringClasses: 'ring-brand-700/50 dark:ring-brand-300/50',
  },
  warning: {
    bgClasses: 'bg-branddim-950/95 dark:bg-branddim-50/95',
    textClasses: 'text-branddim-100 dark:text-branddim-700',
    iconClasses: 'text-branddim-300 dark:text-branddim-600',
    ringClasses: 'ring-branddim-700/50 dark:ring-branddim-300/50',
  },
  info: {
    bgClasses: 'bg-brandcomp-950/95 dark:bg-brandcomp-50/95',
    textClasses: 'text-brandcomp-100 dark:text-brandcomp-700',
    iconClasses: 'text-brandcomp-300 dark:text-brandcomp-600',
    ringClasses: 'ring-brandcomp-700/50 dark:ring-brandcomp-300/50',
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
    bgClasses: 'bg-brand-50/95 dark:bg-brand-950/95',
    textClasses: 'text-brand-700 dark:text-brand-100',
    iconClasses: 'text-brand-600 dark:text-brand-300',
    ringClasses: 'ring-brand-200/50 dark:ring-brand-800/50',
  },
  warning: {
    bgClasses: 'bg-branddim-50/95 dark:bg-branddim-950/95',
    textClasses: 'text-branddim-700 dark:text-branddim-100',
    iconClasses: 'text-branddim-600 dark:text-branddim-300',
    ringClasses: 'ring-branddim-200/50 dark:ring-branddim-800/50',
  },
  info: {
    bgClasses: 'bg-brandcomp-50/95 dark:bg-brandcomp-950/95',
    textClasses: 'text-brandcomp-700 dark:text-brandcomp-100',
    iconClasses: 'text-brandcomp-600 dark:text-brandcomp-300',
    ringClasses: 'ring-brandcomp-200/50 dark:ring-brandcomp-800/50',
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
    bgClasses: 'bg-brand-50/90 dark:bg-brand-950/90',
  },
  warning: {
    ...STANDARD_COLORS.warning,
    bgClasses: 'bg-branddim-50/90 dark:bg-branddim-950/90',
  },
  info: {
    ...STANDARD_COLORS.info,
    bgClasses: 'bg-brandcomp-50/90 dark:bg-brandcomp-950/90',
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
