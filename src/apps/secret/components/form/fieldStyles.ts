// src/apps/secret/components/form/fieldStyles.ts

// Shared shell for the passphrase, TTL, and recipient controls in
// SecretForm.vue. Keep this as the single source of truth for their
// border/background/hover/focus/dark styling so the three fields stay
// visually consistent.
export const FIELD_SHELL =
  'w-full border border-gray-200/60 bg-white/80 backdrop-blur-sm text-sm ' +
  'transition-all duration-300 ' +
  'hover:border-gray-300/80 hover:bg-white/90 ' +
  'focus:border-blue-500/80 focus:bg-white focus:outline-none focus:ring-4 focus:ring-blue-500/20 ' +
  'dark:border-gray-700/60 dark:bg-slate-800/80 dark:text-white ' +
  'dark:hover:border-gray-600/80 dark:hover:bg-slate-800/90 ' +
  'dark:focus:border-blue-400/80 dark:focus:bg-slate-800 dark:focus:ring-blue-400/20';

export const FIELD_ERROR =
  'border-red-500/50 focus:border-red-500 focus:ring-red-500/20';
