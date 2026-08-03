.. A new scriv changelog fragment.

Documentation
-------------

- **API response field semantics documented.** ``docs/api/README.md`` now
  states which secret/receipt fields are deprecated, which are aliases, and
  which are commonly confused for each other:

  - ``custid`` is deprecated — read ``owner_id``. v3 omits it from receipt
    records entirely; v2 still emits it but it is null on every receipt created
    since the v0.24 identifier migration; v1 alone translates it back to an
    email address. The top-level ``custid`` in receipt-list responses is a
    different field — the requesting customer — and is unaffected.
  - ``record.metadata`` in v2 conceal/generate responses is an alias emitting
    the identical object as ``record.receipt``. v1 returns only ``metadata``,
    v3 returns only ``receipt``. The separate ``metadata_path`` /
    ``metadata_url`` aliases on receipt responses remain in v3.
  - ``recipients`` (obscured addresses on the receipt — a joined string in v2,
    an array or ``null`` in v3),
    ``details.recipient`` (an array echoing the submitted request values), and
    ``recipient_name`` (an Incoming-secret display name, null for standard
    secrets) are three distinct fields, now tabulated with their per-version
    types.
