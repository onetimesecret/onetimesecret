.. A new scriv changelog fragment.

Security
--------

- The hardened config and logger YAML loaders now permit ``Date`` and ``Time`` in addition to ``Symbol`` (the recommendation from the original security review). Previously the loaders permitted only ``Symbol``, so an unquoted date or time in a deployment's ``config`` or ``logging`` YAML (e.g. ``expires: 2026-01-02``) raised ``Psych::DisallowedClass`` and prevented boot until every such value was quoted — a latent breaking change. Unquoted dates/times now load as ``Date``/``Time`` instances again, while arbitrary Ruby objects (``!ruby/object``) remain rejected. The runtime loader, the ``deep_clone`` round-trip, and the config validator keep their permitted-class lists symmetric, so a config that validates also boots. (#3498)
