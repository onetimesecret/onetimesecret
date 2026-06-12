.. A new scriv changelog fragment.

Fixed
-----

- MFA enrollment QR codes now encode the secret the server actually
  validates. With HMAC mode enabled the frontend was reconstructing the
  ``otpauth://`` URI from ``otp_raw_secret`` (the setup-handshake key) instead
  of ``otp_setup`` (the HMAC'd key the authenticator must use), so scanned
  codes never matched and setup could not complete. The backend now emits
  Rodauth's authoritative ``provisioning_uri`` and the frontend renders it
  directly without reconstruction. (#3431)
