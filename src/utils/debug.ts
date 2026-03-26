// src/utils/debug.ts

export const DEBUG = process.env.NODE_ENV === 'development';

/**
 * Check if a specific debug channel is enabled via localStorage.
 * Enable in browser console: localStorage.setItem('debug:features', 'true')
 * Disable: localStorage.removeItem('debug:features')
 */
function isDebugEnabled(channel: string): boolean {
  if (typeof window === 'undefined') return false;
  return localStorage.getItem(`debug:${channel}`) === 'true';
}

export const debugLog = {
  init: (msg: string, ...args: any[]) => DEBUG && console.log(`[Init] ${msg}`, ...args),
  route: (msg: string, ...args: any[]) => DEBUG && console.log(`[Route] ${msg}`, ...args),
  component: (msg: string, ...args: any[]) => DEBUG && console.log(`[Component] ${msg}`, ...args),
  store: (msg: string, ...args: any[]) => DEBUG && console.log(`[Store] ${msg}`, ...args),
  timing: (label: string) => {
    if (DEBUG) {
      console.time(label);
      return () => console.timeEnd(label);
    }
    return () => {};
  },

  /**
   * Feature/bootstrap debugging — disabled by default, enable with:
   *   localStorage.setItem('debug:features', 'true')
   */
  features: (tag: string, data?: Record<string, unknown>) =>
    isDebugEnabled('features') && console.debug(`[${tag}]`, data ?? ''),
};
