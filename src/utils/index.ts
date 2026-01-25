// src/utils/index.ts

export * from './color-utils';
export * from './format';
export * from './parse';
export * from './redirect';

const detectPlatform = (ua: string = window.navigator.userAgent): 'safari' | 'edge' => {
  ua = ua.toLowerCase();
  const isMac = /macintosh|mac os x|iphone|ipad|ipod/.test(ua);
  return isMac ? 'safari' : 'edge';
};

export { detectPlatform };
