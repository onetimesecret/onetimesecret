/**
 * Formats a time-to-live value in seconds to a human-readable string
 * @param seconds - The TTL value in seconds
 * @returns A formatted string representing the time period
 */
export const formatTTL = (seconds: number): string => {
  if (seconds >= 86400) return `${Math.floor(seconds / 86400)} days`;
  if (seconds >= 3600) return `${Math.floor(seconds / 3600)} hours`;
  return `${Math.floor(seconds / 60)} minutes`;
};
