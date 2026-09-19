.. A new scriv changelog fragment.

Changed
-------

- Colonel ``PUT /api/colonel/domains/:extid/configs/signin`` answers ``422``
  for a ``related_origins`` entry that belongs to another organization. It
  used to answer ``200`` for an entry that never took effect, because such
  entries are dropped on every read. Canonical hosts, the config's own domain
  and hosts this install does not serve are accepted as before. #4421

Fixed
-----

- The first write of a domain's sign-in config now stores ``related_origins``.
  It was silently dropped while the API reported the field as changed. #4421
