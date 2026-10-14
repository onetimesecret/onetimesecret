.. A new scriv changelog fragment.

Changed
-------

- A custom domain is served only once its ownership is verified, when the
  domain validation strategy checks ownership (``approximated``,
  ``caddy_on_demand``). Until then its host answers 404, the domain is not
  offered for links, and secret creation does not accept it as a share
  domain. Under ``passthrough``, registration by the owning organization is
  enough, as before. A domain record with no organization is not served.
- ``features.domains.serve_unverified`` (``DOMAINS_SERVE_UNVERIFIED``),
  default ``false``, keeps the previous behaviour for domains that have an
  organization when set to ``true``, and logs a warning at boot.
- Before upgrading, run ``bin/ots domains verify --all`` so that domains
  whose TXT record is in place are recorded as verified, and check the
  remaining unverified domains that are still in use. An operator can mark a
  domain verified through the colonel domain override.
