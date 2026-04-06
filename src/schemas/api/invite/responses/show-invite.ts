// src/schemas/api/invite/responses/show-invite.ts
//
// Response schema for InviteAPI::Logic::Invites::ShowInvite
// GET /api/invite/:token
//

import { z } from 'zod';

/**
 * Organization branding schema for invitation display
 */
export const inviteBrandingSchema = z.object({
  primary_color: z.string(),
  display_name: z.string().nullable(),
  logo_url: z.string().nullable(),
  icon_url: z.string().nullable(),
});

export type InviteBranding = z.infer<typeof inviteBrandingSchema>;

/**
 * Auth method schemas - discriminated union for different authentication options
 *
 * - password: Standard email/password authentication
 * - magic_link: Passwordless email authentication
 * - sso: Single sign-on via identity provider (e.g., Entra ID, Google, GitHub)
 */
export const authMethodPasswordSchema = z.object({
  type: z.literal('password'),
  enabled: z.boolean(),
});

export const authMethodMagicLinkSchema = z.object({
  type: z.literal('magic_link'),
  enabled: z.boolean(),
});

export const authMethodSsoSchema = z.object({
  type: z.literal('sso'),
  enabled: z.boolean(),
  provider_type: z.string().optional(),
  display_name: z.string().nullable().optional(),
  platform_route_name: z.string().optional(),
});

export const authMethodSchema = z.discriminatedUnion('type', [
  authMethodPasswordSchema,
  authMethodMagicLinkSchema,
  authMethodSsoSchema,
]);

export type AuthMethod = z.infer<typeof authMethodSchema>;

/**
 * Invitation status values
 */
export const invitationStatusSchema = z.enum([
  'pending',
  'active',
  'expired',
  'declined',
  'revoked',
]);

export type InvitationStatus = z.infer<typeof invitationStatusSchema>;

/**
 * Invitation response schema with enriched fields for state machine
 *
 * Key fields:
 * - account_exists: Whether an account with the invited email already exists
 * - actionable: True only when invitation is pending AND not expired (can be accepted/declined)
 * - auth_methods: Available authentication methods for the invitee
 */
export const showInviteResponseSchema = z.object({
  organization_name: z.string(),
  organization_id: z.string(),
  email: z.string().email(),
  role: z.string(),
  invited_by_email: z.string().nullable(),
  expires_at: z.number(),
  status: invitationStatusSchema,
  account_exists: z.boolean(),
  actionable: z.boolean(),
  branding: inviteBrandingSchema.nullable().optional(),
  auth_methods: z.array(authMethodSchema).optional(),
});

export type ShowInviteResponse = z.infer<typeof showInviteResponseSchema>;
