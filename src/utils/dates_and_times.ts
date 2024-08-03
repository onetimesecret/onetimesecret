
export const formatDate = (epochSeconds: number): string => {
  const date = new Date(epochSeconds * 1000); // Convert seconds to milliseconds
  return date.toLocaleString(); // Or use a more specific format as needed
}
