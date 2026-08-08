.. A new scriv changelog fragment.

Changed
-------

- ``Rack::DetectHost`` now delegates RFC 7239 ``Forwarded`` parsing to
  ``Rack::Utils.forwarded_values``, Rack's hardened quoted-string-aware
  parser with denial-of-service bounds. The earliest ``host=`` parameter
  in the header wins, mirroring the first-value convention already used
  for ``X-Forwarded-Host``. (#4040)
- ``Rack::DetectHost`` rejects detected hosts that fail
  ``DomainParser.basically_valid?``, so header values containing control
  characters, quotes, or other non-hostname junk can no longer become
  the detected host. (#4040)

Fixed
-----

- ``DomainParser.extract_hostname`` now unwraps bracketed IPv6 literals
  (``[2001:db8::1]:8080`` → ``2001:db8::1``) instead of mangling them by
  splitting on the first colon, and returns nil for malformed bracket
  expressions. (#4040)

AI Assistance
-------------

- Claude reviewed #4053, then implemented the Rack delegation, hostname
  validation gate, and IPv6 literal handling with regression tests. (#4040)
