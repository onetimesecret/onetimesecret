// src/utils/url.ts

/**
 * Infer if a URL is external based on scheme.
 * Returns true for http:// and https:// URLs, false for relative paths and other schemes.
 */
export const isExternalUrl = (url: string): boolean => /^https?:\/\//i.test(url);
