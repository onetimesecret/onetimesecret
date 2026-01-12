// src/types/declarations/global.d.ts

import { OnetimeWindow } from './window';

declare global {
  interface Window {
    /** Server-injected bootstrap state (consumed by bootstrap.service.ts) */
    __BOOTSTRAP_STATE__?: OnetimeWindow;

    __VUE_DEVTOOLS_GLOBAL_HOOK__?: {
      enabled: boolean;
    };
  }
}

export {}; // Ensures the file is treated as a module
