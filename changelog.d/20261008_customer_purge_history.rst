Fixed
-----

- Customer purge no longer refuses otherwise eligible accounts solely for
  completed migration metadata, supported legacy creator identifiers, or
  non-live billing history. Live subscriptions, unresolved migration state,
  and ambiguous ownership still block deletion.
