// schemas/errors/classifier.test.ts
import {
  classifyError,
  createError,
  isApplicationError,
  isSecurityIssue,
} from '@/schemas/errors/classifier';
import { describe, expect, it } from 'vitest';

describe('error classifier', () => {
  describe('classifyError', () => {
    it('classifies 403 as security error', () => {
      const error = classifyError({
        message: 'Forbidden',
        status: 403,
      });

      expect(error).toMatchObject({
        message: 'Forbidden',
        type: 'security',
        severity: 'error',
      });
      expect(isSecurityIssue(error)).toBe(true);
    });

    it('classifies 404 as human error', () => {
      const error = classifyError({
        message: 'Not Found',
        status: 404,
      });

      expect(error).toMatchObject({
        message: 'Not Found',
        type: 'human',
        severity: 'error',
      });
    });

    it('classifies unknown status codes as technical errors', () => {
      const error = classifyError({
        message: 'Internal Server Error',
        status: 500,
      });

      expect(error).toMatchObject({
        message: 'Internal Server Error',
        type: 'technical',
        severity: 'error',
      });
    });

    it('preserves existing ApplicationErrors', () => {
      const original = createError('Custom Error', 'security', 'warning');
      const classified = classifyError(original);

      expect(classified).toBe(original); // Should be same reference
      expect(isApplicationError(classified)).toBe(true);
    });

    it('handles non-Error objects', () => {
      const error = classifyError('something went wrong');

      expect(error).toMatchObject({
        message: 'something went wrong',
        type: 'technical',
        severity: 'error',
      });
    });
  });
});
