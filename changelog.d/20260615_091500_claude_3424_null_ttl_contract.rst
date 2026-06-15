.. A new scriv changelog fragment.

Fixed
-----

- V3 secret and receipt response contracts now declare ``secret_ttl``, ``receipt_ttl`` and ``lifespan`` as ``z.number().nullable()`` instead of bare ``z.number()``. The ``safe_dump`` boundary intentionally emits ``null`` for these fields when a secret/receipt has no lifespan set, but the strict non-nullable schema rejected that ``null`` — so ``gracefulParse`` threw and the recipient saw "That information is no longer available" for an unconsumed secret. This is the null half of #3424 that the string-coercion cast did not cover: string-typed records were healed, but lifespan-less records still failed. (#3424)
