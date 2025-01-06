// src/plugins/pinia/index.ts

import { PiniaPlugin, PiniaPluginContext } from 'pinia';
import { apiPlugin } from './apiPlugin';
import { autoInitPlugin } from './autoInitPlugin';
import { logoutPlugin } from './logoutPlugin';
import type { PiniaPluginOptions } from './types';

export * from './types';

/**
 * Main Pinia plugin that composes all core functionality
 */
export const piniaPlugin =
  (options: PiniaPluginOptions = {}): PiniaPlugin =>
  (context: PiniaPluginContext) => {
    const plugins = createCorePlugins(options);

    // Apply plugins in sequence, passing each one the complete context:
    // - `store`: The store being augmented
    // - `pinia`: The Pinia instance
    // - `app`: The Vue app instance
    // - `options`: The store definition options
    return plugins.reduce(
      (extensions, plugin) => ({
        ...extensions,
        ...plugin(context),
      }),
      {}
    );
  };

/**
 * Creates core Pinia plugins with configuration options.
 *
 * Plugin execution order is critical:
 * 1. API plugin must initialize first to ensure HTTP client availability
 * 2. Logout plugin adds store cleanup functionality
 * 3. Auto-init runs last to ensure all plugins are ready
 *
 * @param options Configuration for plugins
 * @returns Array of plugins in required execution order
 *
 * Implementation note:
 * Different plugin prototypes and their implications:
 *
 * 1. Curried (Configurable):
 * ```
 * export function apiPlugin(config?: Config) {
 *   return (context: PiniaPluginContext) => void
 * }
 * usage: pinia.use(apiPlugin(config))
 * ```
 *
 * 2. Direct (Non-configurable):
 * ```
 * export function logoutPlugin(context: PiniaPluginContext) {
 *   // Direct context handling
 * }
 * usage: pinia.use(logoutPlugin)
 * ```
 */
export const createCorePlugins = (options: PiniaPluginOptions = {}): PiniaPlugin[] => [
  // 1. API plugin provides $api instance for HTTP requests
  apiPlugin(options.api),
  // 2. Logout plugin adds $logout for auth state cleanup
  logoutPlugin,
  // 3. Store initializer runs last when all required plugins are ready
  autoInitPlugin(options),
];
