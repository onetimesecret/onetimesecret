.. A new scriv changelog fragment.

Fixed
-----

- ``bin/ots domains doctor`` and ``bin/ots memberships doctor`` now find and
  remove collection entries correctly; check #4 no longer flags every domain.
  ``--repair`` reports only the entries it actually removed.
- The ``bin/ots customers purge --redis-url`` report now counts a customer as
  Stripe-protected when an organization they belong to has Stripe billing.
