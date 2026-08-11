// src/schemas/api/invite/responses/show-invite.ts
//
// Response schema for InviteAPI::Logic::Invites::ShowInvite
// GET /api/invite/:token
//

import { effectiveRestrictToSchema } from '@/schemas/api/domains/responses/signin-config';
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
 *
 * NAMING SEAM: the wire type here is `magic_link` while the `restrict_to`
 * value naming the same method is `email_auth`. They refer to one method.
 * Anything correlating this list with `effective_restrict_to` must map across
 * that seam rather than compare the strings (see AcceptInvite.vue's
 * RESTRICT_TO_METHOD_TYPE).
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
 * - invited_by: Masked inviter display value (e.g. "t***@e***.com"); never a raw email
 * - actionable: True only when invitation is pending AND not expired (can be accepted/declined)
 * - auth_methods: Available authentication methods for the invitee
 *
 * NOTE: There is deliberately no account_exists field — the show endpoint is
 * noauth and must not act as an account-existence oracle (AZ7). The signup
 * flow discovers an existing account only via the signup attempt itself.
 */
export const showInviteResponseSchema = z.object({
  organization_name: z.string(),
  organization_id: z.string(),
  email: z.string().email(),
  role: z.string(),
  invited_by: z.string().nullable(),
  expires_at: z.number(),
  status: invitationStatusSchema,
  actionable: z.boolean(),
  branding: inviteBrandingSchema.nullable().optional(),

  /**
   * Sign-in methods this HOST will actually accept, already filtered by
   * `effective_restrict_to` server-side (ADR-024 A1). Can legitimately be an
   * empty array — an `unavailable` resolution allows nothing — which must
   * never be read as "no restriction".
   *
   * Custom-domain hosts only. On a canonical host the key is absent while
   * `effective_restrict_to` is still present, so drive state off the
   * resolution and treat this as supplementary detail (it is what carries the
   * SSO `platform_route_name` needed to route the invitee).
   */
  auth_methods: z.array(authMethodSchema).optional(),

  /**
   * The request host's resolved sign-in restriction (ADR-024 A2/A11, #4139).
   *
   * Emitted on EVERY host, and computed from the same resolver that gates
   * `POST /api/invite/:token/signup` — so the page can render the method the
   * host actually offers instead of a password form whose submit 404s. The
   * client never re-derives this (A4 deleted exactly that).
   *
   * Reuses the settings API's type rather than declaring a parallel one: the
   * server emits one wire shape for both surfaces.
   *
   * Optional because a pre-#4139 backend does not send it. Absent is treated
   * as unrestricted — permissive on purpose, since failing closed on a
   * missing field would take the invite page dark for every older install.
   */
  effective_restrict_to: effectiveRestrictToSchema.optional(),
});

export type ShowInviteResponse = z.infer<typeof showInviteResponseSchema>;
