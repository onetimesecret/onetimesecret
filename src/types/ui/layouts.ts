// types/ui/layouts.ts

import { AuthenticationSettings, Customer } from '@/schemas/models';

/**
 * Single interface for all layout properties.
 * Update as new fields become necessary.
 */
export interface LayoutProps {
  /* BaseLayout fields */
  authenticated?: boolean;
  colonel?: boolean;
  cust?: Customer;
  onetimeVersion?: string;
  authentication?: AuthenticationSettings;
  plansEnabled?: boolean;
  supportHost?: string;
  globalBanner?: string;
  hasGlobalBanner?: boolean;
  primaryColor?: string;

  /* Common UI toggles */
  displayMasthead?: boolean;
  displayNavigation?: boolean;
  displayLinks?: boolean;
  displayFeedback?: boolean;
  displayVersion?: boolean;
  displayPoweredBy?: boolean;
  displayToggles?: boolean;
}
