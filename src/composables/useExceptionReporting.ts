// composables/useExceptionReporting.ts
import type { ExceptionReport } from '@/types';
import api from '@/utils/api';

export function useExceptionReporting() {
  const reportException = async (report: ExceptionReport) => {
    try {
      await api.post('/api/v2/exception', report);
    } catch (error) {
      console.error('Failed to report exception:', error);
      // Silently fail - we don't want exception reporting failures
      // to impact the user experience
    }
  };

  return {
    reportException
  };
}
