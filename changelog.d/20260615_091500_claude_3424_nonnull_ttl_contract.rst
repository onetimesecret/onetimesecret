.. A new scriv changelog fragment.

Fixed
-----

- Secrets and Receipts now guarantee a non-null integer ``lifespan``/TTL end-to-end, closing the null half of #3424. ``Receipt.spawn_pair`` — the single creation choke point — coerces ``lifespan`` to an Integer, which both stores the correct type (Familia v2 is type-preserving, so a ``String`` would persist as a ``String``) and fixes a latent bug where ``lifespan * 2`` string-multiplied the receipt's expiration. Config normalization now also coerces the confirmed leak path ``features.incoming.default_ttl`` (set from an env var via ERB, so a set ``INCOMING_DEFAULT_TTL`` yielded a ``String``) and hardens ``site.secret_options.default_ttl`` against any non-Integer, not just ``String``. The ``safe_dump`` lambdas emit a plain integer with no ``nil``/``-1`` sentinel, and the V3 ``secret``/``receipt`` contracts keep ``secret_ttl``/``receipt_ttl``/``lifespan`` as strict, non-nullable ``z.number()`` — the read-time enforcement of that invariant. An earlier patch widened those fields to ``z.number().nullable()``; it was reverted because a real record can never have an ambiguous expiration. (#3424, #3299)
