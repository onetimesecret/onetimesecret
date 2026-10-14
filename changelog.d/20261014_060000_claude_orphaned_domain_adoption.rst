.. A new scriv changelog fragment.

Changed
-------

- Adding a custom domain no longer adopts an existing domain record that has
  no organization. The request is answered like a domain registered to
  another organization. An operator can still adopt such a record with
  ``bin/ots domains create``, ``bin/ots domains repair --org-id``,
  ``bin/ots domains transfer`` or the colonel API.
- Operator adoption of a domain record with no organization resets its
  ownership verification and issues a new TXT value, so the new organization
  verifies the domain again. The output lists the per-domain settings, brand
  data and receipts the record kept.
