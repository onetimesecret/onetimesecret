.. A new scriv changelog fragment.

Fixed
-----

- Secret and Receipt API responses now coerce their numeric fields to numbers at the ``safe_dump`` serialization boundary: TTL/lifespan fields (``lifespan``, ``secret_ttl``, ``metadata_ttl``, ``receipt_ttl``) cast to integers, and the ``created``/``updated`` timestamps cast to floats so their sub-second precision (used as sorted-set scores) is preserved. Familia v2 storage is type-preserving, so a record whose numeric fields were ever written as strings (unconverted params, console writes, raw ``HSET``) hydrated them as strings and failed the strict ``z.number()`` V3 schema — recipients saw "That information is no longer available" for secrets that were never consumed, with the sender's dashboard stuck on "Previewed". The cast is a no-op for healthy records and neutralizes affected ones; unset lifespans remain ``null`` and unset receipt ``secret_ttl`` remains ``-1``. (#3424, #3268)

Added
-----

- ``scripts/diagnostics/detect_string_typed_numerics.rb``, a read-only scan that finds Secret/Receipt records whose numeric fields are stored as JSON strings at rest (the corruption behind #3424, distinct from the non-JSON bytes that ``check_raw_email_fields.rb`` finds for #3016). The ``safe_dump`` cast keeps the API correct, but the bytes stay corrupt; this locates them and reports a per-record signature to help trace the writer. (#3424)
