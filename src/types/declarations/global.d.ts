import { OnetimeWindow } from './window';

declare global {
  interface Window extends OnetimeWindow {

    __VUE_DEVTOOLS_GLOBAL_HOOK__?: {
      enabled: boolean;
    };
  }

}

export { }; // Ensures the file is treated as a module
