.. A new scriv changelog fragment.

Fixed
-----

- Secret and Receipt API responses now cast their numeric fields (``lifespan``, ``secret_ttl``, ``metadata_ttl``, ``receipt_ttl``, ``created``, ``updated``) to integers at the ``safe_dump`` serialization boundary. Familia v2 storage is type-preserving, so a record whose numeric fields were ever written as strings (unconverted params, console writes, raw ``HSET``) would hydrate them as strings and fail the strict ``z.number()`` V3 schema — recipients saw "That information is no longer available" for secrets that were never consumed, with the sender's dashboard stuck on "Previewed". The cast is a no-op for healthy records and neutralizes affected ones; unset lifespans remain ``null`` and unset receipt ``secret_ttl`` remains ``-1``. (#3424, #3268)
