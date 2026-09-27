// src/plugins/pinia/types.ts

/**
 * Options the auto-init plugin hands to every store's `init()`.
 *
 * There is no `api` option: stores get their axios instance from
 * `inject('api')`, which appInitializer provides. Passing one here was
 * ignored by every store, with a warning on each store creation.
 */
export interface PiniaPluginOptions {
  deviceLocale?: string;
}
