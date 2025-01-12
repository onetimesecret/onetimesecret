// src/utils/parse/time.ts

import { formatDistanceToNow, formatDistance } from 'date-fns';

export const getTimeAgo = (date: Date) => formatDistanceToNow(date, { addSuffix: true });

export const getTimeRemaining = (end: Date, start: Date = new Date()) => {
  if (end < start) return 'Expired';
  return formatDistance(end, start, { includeSeconds: false });
};

export const calculateProgress = (start: Date, end: Date, now = new Date()) => {
  const total = end.getTime() - start.getTime();
  const elapsed = now.getTime() - start.getTime();
  return Math.min(100, Math.max(0, Math.round((elapsed / total) * 100)));
};
