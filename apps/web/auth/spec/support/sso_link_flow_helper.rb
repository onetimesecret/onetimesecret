# apps/web/auth/spec/support/sso_link_flow_helper.rb
#
# frozen_string_literal: true

# =============================================================================
# SSO account-linking route drivers (#3840)
# =============================================================================
#
# The two post-callback linking flows, driven the way the SPA drives them:
#
#   /auth/link-sso        — Phase 3 signin interstitial: prove the mailbox with
#                           the account password, then bind.
#   /auth/sso-link-confirm — Phase 4 mailbox proof: prove it with an emailed
#                           single-use token instead, for passwordless subjects.
#
# WHY SHARED RATHER THAN MIRRORED PER LANE: each of these had a full/ copy and
# a full_mfa/ copy that were byte-identical, because the ROUTE does not change
# between the lanes — only the assertions do (full_mfa/ expects the bind to be
# DEFERRED behind the OTP step). Mirroring the driver bought nothing and meant
# a route or param rename had to be found in two places. What legitimately
# differs — the expectations, and the OTP machinery in support/mfa_flow_helper.rb
# — stays where it is.
#
# Included explicitly (`include SsoLinkFlowHelper`) rather than auto-included:
# these hit specific routes, so only the linking specs should carry them.
# Request plumbing comes from AuthRequestHelper, which is already auto-included
# into type: :integration and included by MfaFlowHelper.
#
# =============================================================================

module SsoLinkFlowHelper
  # ==========================================================================
  # /auth/link-sso — password-proof interstitial
  # ==========================================================================

  # Pull the challenge token out of a /link-sso/:token redirect Location.
  # Tolerates a trailing query or fragment.
  def token_from_location(location)
    location.to_s.split('/link-sso/').last.to_s.split(/[?#]/).first
  end

  def post_link_sso(token:, password:)
    csrf_json_post('/auth/link-sso', token: token, password: password)
  end

  # ==========================================================================
  # /auth/sso-link-confirm — mailbox-proof confirmation
  # ==========================================================================

  # Read the confirmation context the SPA renders before the user commits.
  def get_confirm(token)
    clear_body_headers
    header 'Accept', 'application/json'
    get "/auth/sso-link-confirm/#{token}"
    last_response
  end

  def post_confirm(token:)
    csrf_json_post('/auth/sso-link-confirm', token: token)
  end

  # Mint the single-use verification a confirm link carries, skipping the email
  # round-trip. password_watermark: 0 is the "no password on file" case that the
  # passwordless subjects in these specs are in; a non-zero value models a
  # subject whose password changed after the link was issued, which must
  # invalidate it.
  def mint_verification(email:, uid:, account_id:, provider: 'oidc',
                        issuer: 'https://issuer.example.com', sid: nil, password_watermark: 0)
    Onetime::SsoLinkVerification.issue(
      provider: provider,
      issuer: issuer,
      uid: uid,
      email: OT::Utils.normalize_email(email),
      account_id: account_id,
      sid: sid,
      password_watermark: password_watermark,
    )
  end
end
