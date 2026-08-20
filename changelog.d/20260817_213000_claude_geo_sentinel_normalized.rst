.. A new scriv changelog fragment.

Changed
-------

- Session geo_country is now normalized at the model boundary: Otto's ``'**'``
  "could not resolve" sentinel is mapped to nil on read and is never persisted,
  so API responses carry either a real ISO 3166-1 alpha-2 code or null. The
  admin and account UIs no longer need (or carry) their own sentinel checks.

Fixed
-----

- The colonel sessions list and per-customer sessions view now fetch session
  metadata sidecars in a single pipelined batch (``load_multi``) instead of up
  to one serial round trip pair per row, removing ~200 sequential Redis round
  trips per 100-row page. A batch failure degrades to the previous per-row
  reads, so single bad records still only affect their own row.
