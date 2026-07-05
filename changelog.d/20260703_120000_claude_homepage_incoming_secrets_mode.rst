.. A new scriv changelog fragment.

Added
-----

- Custom domains can now present the Incoming Secrets form as their public
  homepage. The Domain detail screen replaces the Homepage Secrets on/off
  toggle with a three-way Homepage selector — private landing page, secret
  creation form, or incoming secrets form — stored backend-side as a new
  ``secrets_mode`` field (``create`` | ``incoming``) on the per-domain
  HomepageConfig. The incoming option can only be selected once incoming
  secrets is enabled with at least one recipient (enforced in the UI and by
  ``PUT /homepage-config``), and if incoming later drifts unready — recipients
  removed, incoming disabled, feature flag off, or entitlement lapsed — the
  public homepage fails closed to the private landing page rather than falling
  open to the create form. Anonymous secret creation via the API is likewise
  refused on incoming-mode homepages. Existing domains are unaffected
  (missing ``secrets_mode`` reads as ``create``); the optional
  ``20260703_02_backfill_homepage_secrets_mode`` migration persists the
  explicit default onto legacy records.

Changed
-------

- ``GET /api/incoming/config`` on custom domains now reports
  ``enabled: false`` when the domain's incoming config has no recipients,
  so the /incoming page shows its disabled state instead of an
  unsubmittable form with an empty recipient dropdown.
