//const DEBUG = true;
//
//export const debugLog = (component: string, event: string, data?: any) => {
//  if (DEBUG) {
//    const timestamp = performance.now().toFixed(2);
//    console.log(
//      `[${timestamp}ms] [${component}] ${event}`,
//      data ? data : ''
//    );
//  }
//};

// src/utils/debug.ts
export const DEBUG = process.env.NODE_ENV === 'development';

export const debugLog = {
  init: (msg: string, ...args: any[]) =>
    DEBUG && console.log(`[Init] ${msg}`, ...args),
  route: (msg: string, ...args: any[]) =>
    DEBUG && console.log(`[Route] ${msg}`, ...args),
  component: (msg: string, ...args: any[]) =>
    DEBUG && console.log(`[Component] ${msg}`, ...args),
  store: (msg: string, ...args: any[]) =>
    DEBUG && console.log(`[Store] ${msg}`, ...args),
  timing: (label: string) => {
    if (DEBUG) {
      console.time(label);
      return () => console.timeEnd(label);
    }
    return () => {};
  },
};
