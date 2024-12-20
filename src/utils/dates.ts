
export const formatDate = (epochSeconds: number): string => {
  const date = new Date(epochSeconds * 1000); // Convert seconds to milliseconds
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
