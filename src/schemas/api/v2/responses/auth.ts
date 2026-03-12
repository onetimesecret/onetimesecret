// src/schemas/api/v2/responses/auth.ts
//
// Response schemas for authentication endpoints (Rodauth-compatible format).

import { z } from 'zod';
import {
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
} from '@/schemas/api/auth/endpoints/auth';

// Re-export the schemas under consistent names for the registry
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
