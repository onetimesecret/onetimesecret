// src/plugins/pinia/autoInitPlugin.ts

import { PiniaPluginContext } from 'pinia';
import type { PiniaPluginOptions } from './types';

/**
 * Store initialization must run synchronously to ensure store state
 * is ready before router guards or components access it.
 */
export function autoInitPlugin(options: PiniaPluginOptions = {}) {
  return ({ store }: PiniaPluginContext) => {
    if (typeof store.init === 'function') {
      store.init(options);
    }
  };
}
