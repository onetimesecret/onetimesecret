Fixed
-----

- Frontend diagnostics: every capture the app makes now reaches ``beforeSend``
  with the hint Sentry expects. ``diagnostics.service`` calls
  ``Client.captureException`` directly (to capture against an isolated scope),
  and that method does not build a hint — it forwards the one it is given. It
  was given ``undefined``, so ``hint.originalException`` was never present and
  BOTH rules that read it were silently inert in production: the
  expected-transport-outcome drop (#4286) dropped nothing, and the API-error
  grouping (#4287) fingerprinted nothing, leaving axios failures to fragment
  into a fresh issue per call site per deploy.

- Confirming a password no longer runs the login hook.
  ``Auth::Config.valid_login_and_password?`` (account destroy, change email,
  change password, ``/auth/link-sso``) is a Rodauth *internal request*: it runs
  the real login route to check a credential and discards the result. Its
  session is a bare Hash, so ``session.id`` raised ``NoMethodError``; worse, a
  password *confirmation* was recording ``login_success`` in the auth audit
  stream, attempting a deferred SSO bind, and could fire the new-sign-in
  security alert. ``after_login`` now returns early for internal requests.

- A session cookie carrying bytes that are not valid UTF-8 is rejected instead
  of raising ``ArgumentError`` from ``String#match?`` — that raise reached the
  client as a 500 before any handler ran.

- The custom-domain list no longer fails to parse when a domain's proxy
  ``vhost.keep_host`` arrives as a boolean. It is a third-party passthrough
  field and Approximated documents it as a boolean; the schema declared it
  string-only.

Changed
-------

- v1 API form errors group by endpoint rather than by validation message.
  v1 is unauthenticated and under constant bot traffic, and the default
  grouping key for a message event is the message — so every distinct
  validation string anonymous input could provoke minted its own Sentry issue
  at error level. The message stays the event text (the backend scrubbers still
  see it); the endpoint alone decides the group, and the level drops to
  ``warning``.

- Errors from in-app browsers whose injected bridge never loaded
  (``xbrowser``/``swbrowser is not defined``) join the third-party ignore list.

AI Assistance
-------------

- AI assistance was used to correlate the post-release Sentry issue spike
  against the deployed code, isolate the dead capture-hint contract as the
  cause of the frontend fragmentation, and read the four backend crash
  signatures back to their call sites.
