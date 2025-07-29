// schemas/errors/classifier.test.ts
import { classifyError, createError } from '@/schemas/errors/classifier';
import { errorGuards } from '@/schemas/errors/guards';
import { describe, expect, it } from 'vitest';
import type { AxiosError } from 'axios';
import axios from 'axios';

describe('error classifier', () => {
  describe('classifyError', () => {
    it('classifies 403 as security error', () => {
      // Create a proper AxiosError instance
      const axiosError = new axios.AxiosError(
        'Forbidden',
        '403',
        undefined,
        undefined,
        {
          status: 403,
          statusText: 'Forbidden',
          data: { message: 'Forbidden' },
          headers: {},
          config: {} as any,
        }
      );

      const error = classifyError(axiosError);

      expect(error).toMatchObject({
        type: 'security',
        severity: 'error',
      });
      expect(errorGuards.isSecurityIssue(error)).toBe(true);
    });

    it('classifies 404 as human error', () => {
      // Create a proper AxiosError instance
      const axiosError = new axios.AxiosError(
        'Not Found',
        '404',
        undefined,
        undefined,
        {
          status: 404,
          statusText: 'Not Found',
          data: { message: 'Not Found' },
          headers: {},
          config: {} as any,
        }
      );

      const error = classifyError(axiosError);

      expect(error).toMatchObject({
        message: 'Not Found',
        type: 'human',
        severity: 'error',
      });
    });

    it('classifies unknown status codes as technical errors', () => {
      // Create a proper AxiosError instance
      const axiosError = new axios.AxiosError(
        'Internal Server Error',
        '500',
        undefined,
        undefined,
        {
          status: 500,
          statusText: 'Internal Server Error',
          data: { message: 'Internal Server Error' },
          headers: {},
          config: {} as any,
        }
      );

      const error = classifyError(axiosError);

      expect(error).toMatchObject({
        message: 'Internal Server Error',
        type: 'technical',
        severity: 'error',
      });
    });

    it('classifies axios errors correctly', () => {
      const axiosError = new axios.AxiosError(
        'Request failed with status 429',
        'ERR_BAD_REQUEST',
        undefined,
        undefined,
        {
          status: 429,
          data: { message: 'Too Many Requests' },
        } as any
      ) as AxiosError;

      const error = classifyError(axiosError);

      expect(error).toMatchObject({
        message: 'Too Many Requests',
        type: 'security',
        severity: 'error',
        code: 429,
      });
    });

    it('classifies fetch errors correctly', () => {
      const fetchError = new TypeError('Failed to fetch');
      Object.assign(fetchError, {
        status: 422,
        response: {
          status: 422,
          ok: false,
          statusText: 'Unprocessable Entity',
          json: () => Promise.resolve({ message: 'Validation Failed' }),
          data: { message: 'Validation Failed' },
        },
      });

      const error = classifyError(fetchError);

      expect(error).toMatchObject({
        message: 'Validation Failed',
        type: 'human',
        severity: 'error',
        code: 422,
      });
    });

    it('preserves existing ApplicationErrors', () => {
      const original = createError('Custom Error', 'security', 'warning');
      const classified = classifyError(original);

      expect(classified).toStrictEqual(original); // Deep equality check
      expect(errorGuards.isApplicationError(classified)).toBe(true);
    });

    it('handles non-Error objects', () => {
      const error = classifyError('something went wrong');

      expect(error).toMatchObject({
        message: 'something went wrong',
        type: 'technical',
        severity: 'error',
      });
    });

    describe('jsdom checks', () => {
      it.skip('classifies fetch response errors correctly', async () => {
        // Reason: "Response is not a constructor"
        const response = new Response(JSON.stringify({ message: 'Validation Failed' }), {
          status: 422,
          statusText: 'Unprocessable Entity',
          headers: {
            'Content-Type': 'application/json',
          },
        });

        const error = classifyError(response);

        expect(error).toMatchObject({
          message: 'Validation Failed',
          type: 'human',
          severity: 'error',
          code: 422,
        });
      });

      it('classifies fetch network errors correctly', async () => {
        const networkError = new TypeError('Failed to fetch');
        Object.assign(networkError, {
          status: 0,
          name: 'TypeError',
          message: 'Failed to fetch',
        });

        const error = classifyError(networkError);

        expect(error).toMatchObject({
          message: 'Failed to fetch',
          type: 'technical', // Network errors are technical
          severity: 'error',
          code: 'ERR_GENERIC',
        });
      });
    });
  });
});
