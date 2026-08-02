.. A new scriv changelog fragment.

Changed
-------

- **API v3 receipt shape cleanup.** Two long-standing wart fields are corrected
  in v3 only; v1 and v2 responses are byte-for-byte unchanged.

  - ``recipients`` is now ``null`` or an array of strings. The shared
    serializer emits a single ``", "``-joined string (and ``""`` when the
    secret was never emailed), so a client had to branch on the type; v3
    normalizes it at its own serialization boundary. An empty list is ``null``,
    not ``[]``. Note that ``details.recipient`` (the array echoing the
    submitted request) and ``recipient_name`` (an Incoming-secret display name)
    are different fields and are unchanged.
  - ``custid`` is removed from v3 receipt payloads. It is a deprecated creator
    identifier that new receipts never write, so it has been ``null`` on every
    record created since the identifier migration. Read ``owner_id`` instead —
    it was already present alongside it.

  Applies to every v3 endpoint that returns a receipt: secret conceal/generate,
  receipt read, burn, update, the receipt list, and the guest batch receipts
  endpoint.
