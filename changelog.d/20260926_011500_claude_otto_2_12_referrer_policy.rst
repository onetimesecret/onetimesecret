.. A new scriv changelog fragment.

Security
--------

- The Referrer-Policy is now ``strict-origin`` on every response and in every
  document, and it is one value. Secret URLs keep their path and query out of
  every ``Referer`` header, same-origin navigations included; only
  ``scheme://host[:port]`` may be sent, and nothing on an https to http
  downgrade. Under the previous document policy, ``no-referrer``, browsers
  sent ``Origin: null`` on the native form POST that starts every SSO
  sign-in and the request was refused with 403 before the flow began. What a
  destination can now learn is the origin, which for a custom domain is the
  tenant hostname, never a secret identifier. (#4542)

Changed
-------

- Upgraded otto to 2.12. Otto's ``referrer_policy`` setting replaces its
  hard-coded ``strict-origin-when-cross-origin``, which had overridden the
  application's configured policy on every page Otto served. The HTTP header
  and the ``<meta name="referrer">`` tag now agree.

- A JSON request body can no longer override a path or query value in the
  API's Logic classes, and JSON bodies are ignored on ``GET`` and ``HEAD``.
  The secret and receipt endpoints read the identifier from the matched
  route path directly.
