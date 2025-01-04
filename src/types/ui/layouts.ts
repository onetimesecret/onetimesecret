// types/ui/layouts.ts

import { AuthenticationSettings, Customer } from '@/schemas/models';

/**
 * Core application configuration passed from server
 */
export interface WindowConfig {
  authenticated: boolean;
  colonel: boolean;
  cust?: Customer;
  onetimeVersion: string;
  authentication?: AuthenticationSettings;
  plansEnabled: boolean;
  supportHost: string;
  globalBanner?: string;
  hasGlobalBanner?: boolean;
  primaryColor?: string;
}

/**
 * UI display configuration for layout components
 */
export interface LayoutDisplay {
  displayMasthead: boolean;
  displayNavigation: boolean;
  displayLinks: boolean;
  displayFeedback: boolean;
  displayVersion: boolean;
  displayPoweredBy: boolean;
  displayToggles: boolean;
}

/**
 * Single interface for all layout properties.
 * Update as new fields become necessary.
 */
export type LayoutProps = Partial<WindowConfig & LayoutDisplay>;
