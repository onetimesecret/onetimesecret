.. A new scriv changelog fragment.

Fixed
-----

- V3 contracts now declare the TTL/lifespan fields that ``safe_dump`` can emit as ``null`` with ``z.number().nullable()`` instead of bare ``z.number()``: ``secret_ttl``/``lifespan`` on the secret record, and ``receipt_ttl``/``lifespan`` on the receipt record. When a secret/receipt has no lifespan set, ``safe_dump`` returns ``null`` for these, but the strict non-nullable schema rejected it — so ``gracefulParse`` threw and the recipient saw "That information is no longer available" for an unconsumed secret. This is the null half of #3424 that the string-coercion cast did not cover: string-typed records were healed, but lifespan-less records still failed. The receipt ``secret_ttl`` stays non-nullable because its lambda emits ``-1`` (not ``nil``) for an unset value. (#3424)
