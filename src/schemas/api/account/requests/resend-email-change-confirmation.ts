// src/schemas/api/account/requests/resend-email-change-confirmation.ts
//
// Request schema for AccountAPI::Logic::Account::ResendEmailChangeConfirmation
// POST /resend-email-change-confirmation
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// POST — no body params. Resends confirmation to pending email.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const resendEmailChangeConfirmationRequestSchema = z.object({});

export type ResendEmailChangeConfirmationRequest = z.infer<typeof resendEmailChangeConfirmationRequestSchema>;
