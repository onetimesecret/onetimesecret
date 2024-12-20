
export const toDate = (val: unknown): Date => {
  if (val instanceof Date) return val;
  if (typeof val === 'number') {
    // Convert seconds to milliseconds for Unix timestamps
    return new Date(val * 1000);
  }
  if (typeof val === 'string') {
    const num = Number(val);
    if (!isNaN(num)) {
      return new Date(num * 1000);
    }
    return new Date(val);
  }
  throw new Error('Invalid date value');
};

export const formatDate = (epochSeconds: string | number): string => {
  const date = toDate(epochSeconds);
  return date.toLocaleString(); // Or use a more specific format as needed
}

export const formatRelativeTime = (date: Date | undefined): string => {
  if (!date) return '';

  const now = new Date();
  const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

  if (diffInSeconds < 60) return 'just now';
  if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)} minutes ago`;
  if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)} hours ago`;
  return `${Math.floor(diffInSeconds / 86400)} days ago`;
};
