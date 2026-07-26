.. A new scriv changelog fragment.

Fixed
-----

- Numeric ``bin/ots`` options now take effect. Dry::CLI does not implement
  ``type: :integer`` or ``type: :float`` — the symbols are accepted and ignored
  — so a supplied flag reached the command as a string while an omitted one kept
  its declared numeric default. Every such option was bimodal, and eleven were
  outright broken: ``ots status --watch`` and ``ots queue status --watch``
  (``TypeError`` from ``sleep``, so watch mode never worked at all),
  ``ots queue dlq replay --count`` and ``ots housekeeping run --limit``
  (``ArgumentError`` from a comparison), ``ots domains list --limit``,
  ``ots domains verify --limit``, ``ots organizations --list --limit``,
  ``ots billing products events --limit`` (``TypeError`` from ``Array#take`` /
  ``Array#first``), ``ots billing webhooks replay --limit``, and
  ``ots banner set --ttl``. ``ots queue dlq show --index`` silently matched
  nothing.

- Non-numeric input to a numeric option is now rejected with a clear message and
  a non-zero exit instead of being passed through untouched. Previously
  ``--limit abc`` reached the underlying operation as the string ``"abc"``; in
  ``ots bannedips ban --expiration abc`` it became a permanent ban, and in
  ``ots email sync-feedback --limit abc`` it silently requested the 5000-record
  maximum. Values are parsed as base 10, so ``--timeout 010`` means 10 rather
  than octal 8.

Changed
-------

- ``ots server`` now applies its "config file or command-line options, but not
  both" rule to ``--threads`` and ``--bind``, which previously escaped it
  entirely: ``ots server --threads 4:8 config/puma.rb`` was silently accepted
  and the thread setting discarded. The rule compares against declared defaults,
  so passing an option set to its default value alongside a config file is
  accepted. ``--server`` and ``--environment`` remain unguarded.
