.. A new scriv changelog fragment.

Fixed
-----

- **SSO sign-in no longer freezes when the IdP returns no usable email.** When an identity provider (Entra ID, OIDC, …) authenticates a user but supplies no usable email claim, the OmniAuth callback redirects to ``/signin?auth_error=invalid_email`` and the sign-in page now reliably renders a localized error instead of a blank/"frozen" loading screen. The frontend now shows a message for *any* ``auth_error`` code — unrecognized codes (e.g. from a backend newer than the deployed bundle) fall back to a generic SSO-failure message rather than rendering nothing — and the backend callback guard now also rejects an empty local part (``@example.com``) so it can no longer fall through to account creation and 500. This is a stopgap for the frozen-screen symptom; supplying a stable identifier fallback (UPN/``oid``) for emailless SSO users is tracked separately. (#3478)
