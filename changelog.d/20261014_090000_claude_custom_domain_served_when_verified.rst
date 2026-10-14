.. A new scriv changelog fragment.

Changed
-------

- A custom domain is served only once its ownership is verified, when the
  domain validation strategy checks ownership (``approximated``,
  ``caddy_on_demand``). Until then its host answers 404, the domain is not
  offered for links, adding it does not select it for new links, and secret
  creation does not accept it as a share domain. Under ``passthrough``,
  registration by the owning organization is enough, as before. A domain
  record with no organization is not served.
- Under those strategies, a domain whose verification later fails stops
  being served: when a check no longer finds its TXT record, the domain
  loses its verified state (unless a colonel override holds it) and its host
  answers 404 until a check finds the record again. The domain verification
  page now says to keep the TXT record in place.
- ``features.domains.serve_unverified`` (``DOMAINS_SERVE_UNVERIFIED``),
  default ``false``, keeps the previous behaviour for domains that have an
  organization when set to ``true``, and logs a warning at boot.
- Before upgrading, run ``bin/ots domains verify --all`` so that domains
  whose TXT record is in place are recorded as verified, and check the
  remaining unverified domains that are still in use. An operator can mark a
  domain verified through the colonel domain override.
- Before upgrading, also run ``bin/ots domains orphaned``. The domain records
  it lists have no organization and are no longer served; an operator can
  adopt one for an organization (see the orphaned domain adoption entry).
- After switching ``validation_strategy``, run ``bin/ots domains verify
  --all`` before the deployment takes traffic. Serving follows each domain's
  stored ownership state, and only a check under the new strategy updates
  it.
