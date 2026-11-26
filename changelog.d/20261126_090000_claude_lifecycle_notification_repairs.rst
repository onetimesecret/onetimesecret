Fixed
-----

- Owners who turned on reveal notifications now get one email for every
  reveal, whichever API version or route revealed the secret. Before, only
  the v3 reveal route sent it; v1 reveals, v2 reveals, and v2/v3 secret
  views with ``continue=true`` sent nothing. Revealing an account
  verification link still sends no notice.
- The reveal notice and the expiration warning now go out from the custom
  domain's sender when the secret was shared from a custom domain. The
  expiration warning is now sent in the owner's language.
- The expiration warning is no longer sent for a secret that was already
  revealed or burned, and never for an account verification link.
