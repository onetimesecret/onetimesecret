// src/tests/setup/setup-env.ts

import type { OnetimeWindow } from '@/types/declarations/window';

(window as OnetimeWindow).__ONETIME_STATE__ = {
  supported_locales: ['en', 'fr_CA', 'de_AT'],
  fallback_locale: 'en',
  default_locale: 'en',
  locale: 'en',
  authenticated: false,
};

console.log('Window state initialized in setup-env.js');
