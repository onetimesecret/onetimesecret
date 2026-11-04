.. A new scriv changelog fragment.

Changed
-------

- Under the ``approximated`` domain validation strategy, the virtual host at
  the certificate provider is now created when a domain's ownership is
  verified, not when the domain is added. Adding a domain registers the
  record and shows the TXT challenge; the first verification that finds the
  record (or an operator override) creates the virtual host, and the
  scheduled domain refresh does the same for a verified domain that has
  none. A domain whose owner never proves it gets no virtual host and no
  certificate. Virtual hosts created before this change are left in place.
- Until a domain is verified, its status check reports the missing virtual
  host as a known state rather than a failed read, so the domain shows
  "Pending verification" instead of a stale "Unverified" badge.
- ``bin/ots domains create`` no longer takes ``--cert`` / ``--no-cert`` and no
  longer reports a certificate request; run ``bin/ots domains verify`` after
  the TXT record is in place. The colonel create response is unchanged.
