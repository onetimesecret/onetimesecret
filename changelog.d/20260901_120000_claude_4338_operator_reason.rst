.. A new scriv changelog fragment.

Added
-----

- Destructive operator actions now accept an optional **reason** for the
  operator audit trail, through the Colonel console, API, and supported CLI
  commands (#4338).

Changed
-------

- Reasons remain optional. Blank values are omitted; nonblank values are trimmed
  and stored up to 255 characters. Audit-log readers and exports can view the
  stored text (#4338).
