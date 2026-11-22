.. A new scriv changelog fragment.

Security
--------

- Upgraded sanitize to 7.0.2, which fixes GHSA-599p-54q3-ff89 and
  GHSA-mg79-gw37-jxx7, and raised the Gemfile floor to that version.
  sanitize 7.0.2 requires nokogiri 1.19.7 or later.
- Upgraded puma to 7.2.2, which fixes GHSA-86xc-wrr9-xmmq,
  GHSA-jm4r-w4xx-qxw7, GHSA-m5xw-3hrw-qcmf, GHSA-r885-m39c-939g,
  GHSA-rf6g-xhmp-gm7v, GHSA-x646-wp7c-h9mg and GHSA-xw3h-pgr9-3vg7. The
  Gemfile now requires puma 7.2.2 or later; puma 6 is no longer allowed.
  No configuration change.
