.. A new scriv changelog fragment.

Fixed
-----

- A custom domain lookup by name now returns a record only when that record
  is stored under the name looked up. An index entry that names a record
  stored under another name (index drift) is refused and logged for repair,
  and the record stays reachable under its own name. Applies to every lookup
  (request host, ACME on-demand TLS, share domain resolution).
- Deleting a custom domain releases its index entries under the name as
  stored, whatever the copy being deleted holds in memory, so an entry can
  no longer outlive its record. Each release is ownership-checked: deleting a
  drift-produced shadow record that shares a hostname with the record the
  index names leaves that record's entries in place. ``bin/ots domains
  remove`` and the colonel removal no longer carry a survivor re-assertion
  step or a ``reasserts_survivor`` field; its work is done by the deletion
  itself.
- A full write of a stored custom domain runs under WATCH of its record. A
  record deleted between the write's read and its commit is no longer stored
  again by that write; the write is refused instead. A record another writer
  changed in between is read and written again.
