.. A new scriv changelog fragment.

Changed
-------

- Colonel ``PUT /api/colonel/domains/:extid/configs/signin`` answers ``422``
  for a ``related_origins`` entry that belongs to another organization. It
  used to answer ``200`` for an entry that never took effect, because such
  entries are dropped on every read. Canonical hosts, the config's own domain
  and hosts this install does not serve are accepted as before. #4421
- That ``422``, and the one for a malformed ``related_origins`` entry, carry
  ``field: "related_origins"`` and an ``error_key``
  (``api.domains.errors.related_origins_foreign_organization``,
  ``api.domains.errors.related_origins_invalid``), so the message is localized
  and names the refused entries. The colonel console shows it against the
  Related passkey origins field, marks the field invalid and moves focus to
  it; the field's help text now says entries are origins
  (``https://host``), not bare domains. #4421

Fixed
-----

- The first write of a domain's sign-in config now stores ``related_origins``.
  It was silently dropped while the API reported the field as changed. #4421
