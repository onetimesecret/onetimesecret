.. A new scriv changelog fragment.

Changed
-------

- Homepage mode ``matching_cidrs`` entries now match at full precision,
  down to a single host (/32 for IPv4, /128 for IPv6). Entries narrower
  than /24 or /48 used to be dropped at request time with a log warning;
  they now take effect. A ``mode: external`` entry that was dropped before
  will now show its visitors the disabled homepage. The match is a yes or
  no answer from the IP privacy middleware; with IP privacy on (the
  default) the app still sees only the masked client IP (#4056).
