Fixed
-----

- Verified owners who turned on reveal notifications now get one email
  for every reveal, whichever API version or route revealed the secret. Before, only
  the v3 reveal route sent it; v1 reveals, v2 reveals, and v2/v3 secret
  views with ``continue=true`` sent nothing. Revealing an account
  verification link still sends no notice. (!5006)
- The reveal notice and the expiration warning now go out from the custom
  domain's sender when an organization created the secret on its custom
  domain through the v2 or v3 API and still holds that domain. Other
  secrets, including v1 and incoming secrets, use the default sender. The
  expiration warning is now sent in the owner's language. (!5006)
- The expiration warning is no longer sent for a secret that was already
  revealed or burned, and never for an account verification link. (!5006)
- The reveal notice and the expiration warning now go only to owners
  whose account is verified. Owners with an unverified account no longer
  get the reveal notices the v3 reveal route used to send them, nor
  expiration warnings. (!5006)
