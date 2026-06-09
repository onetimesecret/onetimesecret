// src/shared/components/ui/notifications/index.ts
//
// Notification components split into two families:
//
// global/  — viewport-teleported, driven by notificationsStore
//   NotificationHost   mount once in App.vue; `variant` prop selects the visual
//   NotificationPill   small corner pill (default)
//   NotificationCard   corner card with dismiss + progress bar
//   NotificationBanner full-width edge bar with dismiss + progress bar
//
// inline/  — positioned relative to a parent, driven by local props
//   InlineToast        dark pill for ephemeral confirmations ("Copied!")

// Global (store-driven, teleported to body)
export {
  NotificationHost,
  NotificationPill,
  NotificationCard,
  NotificationBanner,
} from './global';

// Inline (prop-driven, parent-relative)
export { InlineToast } from './inline';

// Shared severity config
export { getSeverityMeta, getInvertedColors, getStandardColors, getBannerColors } from './severityConfig';
export type { SeverityMeta, SeverityColors } from './severityConfig';
