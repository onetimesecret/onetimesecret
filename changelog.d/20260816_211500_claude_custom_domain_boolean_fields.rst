.. A new scriv changelog fragment.

Fixed
-----

- Custom domains showed the wrong verification status in the workspace and
  colonel UIs. The ``resolving`` flag — "the domain has a valid A or CNAME
  record" — was never included in the domain API payload at all, so the
  frontend had nothing to distinguish a domain whose DNS resolves from one
  that does not, and fell back to reading it off ``vhost.status``. It is now
  a declared safe-dump field alongside ``verified``.

- ``verified``, ``resolving`` and ``favicon_fetched`` on a custom domain are
  now stored as real booleans and coerced on every write. These fields had
  accumulated mixed spellings across rows — ``true``, ``'true'``, ``'1'``,
  ``nil`` — because a plain field stores whatever the caller hands it, and
  each of the nine places that read them re-implemented the comparison. Some
  used ``.to_s == 'true'``, which silently returns false for a row written as
  a native boolean; one write path (the ``field!`` fast writer, which domain
  verification uses) bypassed coercion entirely. Reads now heal legacy
  spellings on load, so no data migration is required.

AI Assistance
-------------

- Claude extended ``BooleanFieldType`` with a declared storage encoding
  (``:native`` for these fields; the grandfathered ``:string`` remains the
  default so Customer's ``verified``/``suspended`` rows are untouched), moved
  coercion onto the setter and the fast writer, converted the nine consumer
  sites off their bespoke comparisons, and wrote the regression coverage that
  pins the persisted bytes on both write paths.
