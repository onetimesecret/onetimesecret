.. A new scriv changelog fragment.

Security
--------

- **API v2 Basic auth now fails closed.** Routes that accept either API
  credentials or anonymous access (``auth=basicauth,noauth`` — secret conceal,
  generate, reveal, receipt read/burn/update) treated a chain of strategies as
  OR logic, so a request presenting *invalid* Basic credentials fell through to
  the anonymous strategy and succeeded: HTTP 200 with the secret created under
  no owner. A caller whose API key was wrong, revoked, or whose username was an
  organization ID or ``owner_id`` instead of the account email or customer ID
  (``ur…``) silently got anonymous behaviour — anonymous TTL, no receipt in
  their account, no error. Rejected credentials now produce 401 with the
  original failure reason. Requests that present no ``Authorization`` header at
  all are unaffected and remain anonymous.

- Anonymous secret TTLs are now bounded by a ceiling that is read on every
  deployment, closing a policy inversion where an anonymous request could
  outlive an authenticated free-tier one (which is denied above 14 days with an
  upgrade prompt). The ceiling defaults to 7 days; a configured ``ttl_options``
  maximum below it still wins, and with billing enabled the free-tier
  ``secret_lifetime`` limit applies as well. See the note below for the
  self-hosted override.

- A recipient email supplied without an account now raises 401 rather than a
  422 field-validation error, correctly signalling an authentication failure.

.. note::

   **Operators behind an htpasswd-style reverse proxy:** strip the
   ``Authorization`` header before proxying to ``/api/v2``. A forwarded proxy
   credential is now read as a presented API credential, and an *anonymous*
   request carrying one gets 401. Session-authenticated requests are not
   affected — a valid session cookie outranks a stray or cached
   ``Authorization`` header, so the web UI keeps working either way.
