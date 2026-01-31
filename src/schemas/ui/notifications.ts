// src/schemas/ui/notifications.ts

/**
 * Notification-related types
 *
 * Extends error severity with success state for UI notifications.
 */

import type { ErrorSeverity } from '@/schemas/errors';

/**
 * Notification severity levels
 *
 * Extends ErrorSeverity with 'success' for positive feedback
 * and null for dismissed/hidden state.
 */
export type NotificationSeverity = ErrorSeverity | 'success' | null;
