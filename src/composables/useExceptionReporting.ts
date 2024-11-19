// composables/useExceptionReporting.ts
import api from '@/utils/api';
import type { ExceptionReport } from '@/types';

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
