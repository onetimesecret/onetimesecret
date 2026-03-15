// src/schemas/api/v3/responses/auth.ts
//
// Authentication response schemas. These already use JSON-native types
// (no transforms) so V3 re-exports them from the auth module.

import {
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
} from '@/schemas/api/auth/endpoints/auth';
import { z } from 'zod';

export {
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
};

export type LoginResponse = z.infer<typeof loginResponseSchema>;
export type CreateAccountResponse = z.infer<typeof createAccountResponseSchema>;
export type LogoutResponse = z.infer<typeof logoutResponseSchema>;
export type ResetPasswordRequestResponse = z.infer<typeof resetPasswordRequestResponseSchema>;
export type ResetPasswordResponse = z.infer<typeof resetPasswordResponseSchema>;
