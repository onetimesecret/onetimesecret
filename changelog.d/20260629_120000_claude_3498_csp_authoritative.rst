.. A new scriv changelog fragment.

Security
--------

- When the Content-Security-Policy is enabled (``site.security.csp.enabled == true``), the application's hardened nonce-based policy now takes precedence over any pre-existing or upstream policy. Previously ``add_response_headers`` returned early if a ``content-security-policy`` header was already set, so a weaker policy injected by upstream middleware could silently bypass the hardened nonce-only policy. The app now overrides it (logging the override for visibility). When CSP is disabled, any pre-existing header is left untouched. (#3498)
