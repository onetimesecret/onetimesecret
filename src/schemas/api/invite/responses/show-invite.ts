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
 * value naming the same method is `email_auth` (the restrict_to vocabulary is
 * `password | email_auth | webauthn | sso` — see `restrictToSchema` in
 * @/schemas/contracts/bootstrap.ts). They are one method under two names, and
 * only this one pair differs; `password` and `sso` are spelled identically on
 * both sides.
 *
 * So anything correlating this list with `effective_restrict_to` must translate
 * `magic_link` <-> `email_auth` rather than compare the strings — a direct
 * comparison silently drops the one method the host does offer. The server
 * already applies that translation when it builds this list: see
 * `build_auth_methods` in apps/api/invite/logic/invites/show_invite.rb, which
 * asks the resolution about 'email_auth' while emitting type 'magic_link'.
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
  /**
   * TENANT SSO ONLY: the domain's own SsoConfig provider type ('oidc' |
   * 'entra_id', CustomDomain::SsoConfig::PROVIDER_TYPES). ABSENT on
   * platform-fallback entries — platform providers are identified by
   * `platform_route_name`, and their registry vocabulary (oidc, entra, google,
   * github) is a different namespace from the tenant one, so there is no
   * honest value to fill in. Never branch on this to decide whether an entry
   * is routable; branch on `platform_route_name`, which both arms carry.
   */
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
   * `effective_restrict_to` server-side
   * (ADR-034#restrict-to-is-an-access-control-not-a-display-preference). Can
   * legitimately be an empty array — an `unavailable` resolution allows
   * nothing — which must never be read as "no restriction".
   *
   * Custom-domain hosts only. On a canonical host the key is absent while
   * `effective_restrict_to` is still present, so drive state off the
   * resolution and treat this as supplementary detail (it is what carries the
   * SSO `platform_route_name` needed to route the invitee).
   */
  auth_methods: z.array(authMethodSchema).optional(),

  /**
   * The request host's resolved sign-in restriction
   * (ADR-034#resolution-is-model-owned / #invite-signup-is-gated, #4139).
   *
   * Emitted on EVERY host, and computed from the same resolver that gates
   * `POST /api/invite/:token/signup` — so the page can render the method the
   * host actually offers instead of a password form whose submit 404s. The
   * client never re-derives this
   * (ADR-034#settings-api-serializes-effective-restrict-to deleted exactly that).
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
