.. A new scriv changelog fragment.

Fixed
-----

- Czech and Dutch UI copy that had drifted out of each locale's locked
  informal register is corrected: Czech now uses the informal ``ty``
  possessives/pronouns throughout (13 strings), and Dutch now uses informal
  ``je``/``jouw`` across all flagged copy — product UI, plus the
  legal/marketing strings that had used formal ``u``/``uw`` (34 strings total).
  Surfaced by the resolver-engine register gate; both locales now scan clean.
  (#3530)
