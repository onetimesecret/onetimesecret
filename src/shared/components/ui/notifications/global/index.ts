// src/shared/components/ui/notifications/global/index.ts
//
// Global (viewport-teleported, store-driven) notification components.
//
// NotificationHost — the harness; mount once in App.vue
// NotificationPill — small corner pill (default production style)
// NotificationCard — corner card with dismiss + progress bar
// NotificationBanner — full-width edge bar with dismiss + progress bar

export { default as NotificationHost } from './NotificationHost.vue';
export { default as NotificationPill } from './NotificationPill.vue';
export { default as NotificationCard } from './NotificationCard.vue';
export { default as NotificationBanner } from './NotificationBanner.vue';
