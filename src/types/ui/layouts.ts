// types/ui/layouts.ts

import { AuthenticationSettings, Customer } from '@/schemas/models';

/**
 * Logo configuration for masthead and other layout components
 */
export interface LogoConfig {
  /** Logo URL (image path or component name ending with .vue) */
  url?: string;
  /** Logo alt text (falls back to i18n key) */
  alt?: string;
  /** Link destination for logo (defaults to '/') */
  href?: string;
  /** Logo size in pixels (defaults to 64) */
  size?: number;
  /** Whether to show company name next to logo */
  showCompanyName?: boolean;
  /** Company name override (falls back to config or i18n) */
  companyName?: string;
  /** Color mode for logo display */
  mode?: 'light' | 'dark';
  /** Custom aria label override */
  ariaLabel?: string;
}
/**
 * Core application configuration passed from server
 *
 * @deprecated Components use WindowService to access this data
 * now. Keeping for reference until all components are updated.
 *
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
  displayGlobalBroadcast: boolean;
  displayMasthead: boolean;
  displayNavigation: boolean;
  displayFooterLinks: boolean;
  displayFeedback: boolean;
  displayVersion: boolean;
  displayPoweredBy: boolean;
  displayToggles: boolean;
}

/**
 * Single interface for all layout properties.
 * Update as new fields become necessary.
 */
export interface LayoutProps extends Partial<LayoutDisplay> {
  /** Logo configuration for the layout */
  logo?: LogoConfig;
  /** Colonel mode enables admin features */
  colonel?: boolean;
}
