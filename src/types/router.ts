// src/types/router.ts

/**
 * Type extension for route meta to include title property
 * Used by router configuration and page title management
 */
export interface RouteMeta {
  title?: string;
  requiresAuth?: boolean;
  isAuthRoute?: boolean;
  layout?: string;
  layoutProps?: Record<string, unknown>;
}
