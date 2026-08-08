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
  resolved the PROXY address as the client. IP rate limits, bans, and audit
  attribution all keyed on the proxy — and because the masked proxy address
  stays private, access controls that match the resolved IP against private
  ranges passed for EVERY proxied request: depth-mode operators using
  admin/colonel network isolation (``admin.allowed_cidrs`` with private
  ranges, as the operations doc recommends) or health-endpoint access
  control should audit access logs for the affected window. Meanwhile a
  client that smuggled one forged leftmost ``X-Forwarded-For`` entry past
  the proxy got the forged value resolved as its client IP. The depth value
  now maps directly (``trusted_proxy_depth = depth``), which resolves the
  true client on honest chains and never selects a forged leftmost entry:
  positions are counted raw from the right, so left-side padding cannot
  shift the selection. The depth must match the real hop count, each hop
  appending exactly one entry — a shorter chain falls back to the peer,
  while a depth larger than the real hop count selects a client-supplied
  entry (keep the edge locked down).
  Operators who compensated for the bug by setting ``depth`` one lower than
  their real hop count should correct it to the actual number of proxies.
  (#4024)
