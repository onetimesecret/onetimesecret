.. A new scriv changelog fragment.

Changed
-------

- ``Rack::DetectHost`` parses ``Forwarded`` via
  ``Rack::Utils.forwarded_values`` instead of a hand-rolled scanner.
  When the framework already ships a hardened parser — quoting,
  escapes, DoS bounds — delegate; don't reimplement. Earliest
  ``host=`` wins, matching the ``X-Forwarded-Host`` first-value
  convention. (#4040)
- Detected hosts must pass ``DomainParser.basically_valid?`` —
  extract, then validate, the same gate ``DomainStrategy`` already
  applies. (#4040)

Fixed
-----

- ``DomainParser.extract_hostname`` now unwraps bracketed IPv6 literals
  (``[2001:db8::1]:8080`` → ``2001:db8::1``) instead of mangling them by
  splitting on the first colon. Bracket contents must parse as IPv6 —
  malformed or counterfeit literals (``[dead.beef]``) return nil. (#4040)

AI Assistance
-------------

- Claude reviewed #4053, then implemented the Rack delegation, hostname
  validation gate, and IPv6 literal handling with regression tests. (#4040)
