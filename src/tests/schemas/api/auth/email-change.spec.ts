// src/tests/schemas/api/auth/email-change.spec.ts

// Tests for email change Zod schemas: emailChangeRequestResponseSchema
// and emailChangeConfirmResponseSchema, validating API response shapes
// for the email change flow.

import { describe, it, expect } from 'vitest';
import {
  emailChangeRequestResponseSchema,
  emailChangeConfirmResponseSchema,
  isAuthError,
} from '@/schemas/api/auth/endpoints/auth';

describe('emailChangeRequestResponseSchema', () => {
  describe('success responses', () => {
    it('accepts { sent: true }', () => {
      const result = emailChangeRequestResponseSchema.parse({
        sent: true,
      });
      expect(result).toEqual({ sent: true });
    });

    it('accepts { sent: false }', () => {
      const result = emailChangeRequestResponseSchema.parse({
        sent: false,
      });
      expect(result).toEqual({ sent: false });
    });
  });

  describe('error responses', () => {
    it('accepts error with message only', () => {
      const result = emailChangeRequestResponseSchema.parse({
        error: 'Email address is already in use',
      });
      expect(result).toEqual({
        error: 'Email address is already in use',
      });
    });

    it('accepts error with field-error tuple', () => {
      const result = emailChangeRequestResponseSchema.parse({
        error: 'Validation failed',
        'field-error': ['new_email', 'is not a valid email'],
      });
      expect(result).toEqual({
        error: 'Validation failed',
        'field-error': ['new_email', 'is not a valid email'],
      });
    });

    it('identifies error responses via isAuthError', () => {
      const errorResponse = emailChangeRequestResponseSchema.parse({
        error: 'Something went wrong',
      });
      expect(isAuthError(errorResponse)).toBe(true);
    });

    it('identifies success responses as non-errors via isAuthError', () => {
      const successResponse = emailChangeRequestResponseSchema.parse({
        sent: true,
      });
      expect(isAuthError(successResponse)).toBe(false);
    });
  });

  describe('malformed payloads', () => {
    it('rejects empty object', () => {
      expect(() =>
        emailChangeRequestResponseSchema.parse({})
      ).toThrow();
    });

    it('rejects payload with wrong field name', () => {
      expect(() =>
        emailChangeRequestResponseSchema.parse({
          success: 'Email sent',
        })
      ).toThrow();
    });

    it('rejects payload with sent as string', () => {
      expect(() =>
        emailChangeRequestResponseSchema.parse({
          sent: 'true',
        })
      ).toThrow();
    });

    it('rejects field-error with wrong tuple shape', () => {
      expect(() =>
        emailChangeRequestResponseSchema.parse({
          error: 'Validation failed',
          'field-error': ['only_one_element'],
        })
      ).toThrow();
    });
  });
});

describe('emailChangeConfirmResponseSchema', () => {
  describe('success responses', () => {
    it('accepts { confirmed: true, redirect: "/signin" }', () => {
      const result = emailChangeConfirmResponseSchema.parse({
        confirmed: true,
        redirect: '/signin',
      });
      expect(result).toEqual({
        confirmed: true,
        redirect: '/signin',
      });
    });

    it('accepts confirmed with any redirect path', () => {
      const result = emailChangeConfirmResponseSchema.parse({
        confirmed: true,
        redirect: '/dashboard',
      });
      expect(result).toEqual({
        confirmed: true,
        redirect: '/dashboard',
      });
    });
  });

  describe('error responses', () => {
    it('accepts error with message only', () => {
      const result = emailChangeConfirmResponseSchema.parse({
        error: 'This link has expired',
      });
      expect(result).toEqual({
        error: 'This link has expired',
      });
    });

    it('accepts error with field-error tuple', () => {
      const result = emailChangeConfirmResponseSchema.parse({
        error: 'Invalid token',
        'field-error': ['token', 'has expired'],
      });
      expect(result).toEqual({
        error: 'Invalid token',
        'field-error': ['token', 'has expired'],
      });
    });

    it('identifies error responses via isAuthError', () => {
      const errorResponse = emailChangeConfirmResponseSchema.parse({
        error: 'Expired link',
      });
      expect(isAuthError(errorResponse)).toBe(true);
    });
  });

  describe('malformed payloads', () => {
    it('rejects empty object', () => {
      expect(() =>
        emailChangeConfirmResponseSchema.parse({})
      ).toThrow();
    });

    it('rejects confirmed without redirect', () => {
      expect(() =>
        emailChangeConfirmResponseSchema.parse({
          confirmed: true,
        })
      ).toThrow();
    });

    it('rejects redirect without confirmed', () => {
      expect(() =>
        emailChangeConfirmResponseSchema.parse({
          redirect: '/signin',
        })
      ).toThrow();
    });

    it('rejects confirmed as string', () => {
      expect(() =>
        emailChangeConfirmResponseSchema.parse({
          confirmed: 'true',
          redirect: '/signin',
        })
      ).toThrow();
    });

    it('rejects redirect as number', () => {
      expect(() =>
        emailChangeConfirmResponseSchema.parse({
          confirmed: true,
          redirect: 404,
        })
      ).toThrow();
    });
  });
});
