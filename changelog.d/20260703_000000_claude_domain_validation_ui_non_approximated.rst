.. A new scriv changelog fragment.

Changed
-------

- Custom-domain screens no longer show Approximated-based DNS status (the
  "Inactive"/"DNS incorrect" badges and verification flow) on installs that
  don't use the ``approximated`` validation strategy. Self-hosted and custom
  installs manage their own DNS and TLS, so those badges — which only ever
  populate from Approximated's per-domain check — previously made every domain
  look permanently invalid. Adding a domain on such installs now opens a simple
  DNS-setup screen showing the CNAME record to point at the canonical domain,
  instead of the Approximated verification screen.
