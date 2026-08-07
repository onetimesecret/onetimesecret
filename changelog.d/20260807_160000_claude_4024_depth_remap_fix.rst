.. A new scriv changelog fragment.

Fixed
-----

- ``TRUSTED_PROXY_MODE=depth`` now resolves the real client IP. The
  YAML→otto translator added 1 to the configured ``depth`` (the otto#151
  remap), which double-counted the connecting peer: otto's hop chain is
  ``X-Forwarded-For + [REMOTE_ADDR]`` with the client selected at
  ``chain[-(depth+1)]``, so ``depth: N`` already means "N proxy hops,
  counting the peer as hop 1" — exactly what the config documents
  ("1 = standard single reverse proxy"). Under the remap, every honest
  request in a documented topology hit otto's short-chain fallback and
  resolved the PROXY address as the client (IP rate limits, bans, and audit
  attribution all keyed on the proxy), while a client that smuggled one
  forged leftmost ``X-Forwarded-For`` entry past the proxy got the forged
  value resolved as its client IP. The depth value now maps directly
  (``trusted_proxy_depth = depth``), which resolves the true client on
  honest chains and never selects a forged leftmost entry (positions are
  counted raw from the right). Operators who compensated for the bug by
  setting ``depth`` one lower than their real hop count should correct it to
  the actual number of proxies. (#4024)
