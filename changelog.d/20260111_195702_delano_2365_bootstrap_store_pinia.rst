Changed
-------

- Replace WindowService with Pinia-based bootstrapStore as single source of truth for server-injected state
- Rename window variable from ``__ONETIME_STATE__`` to ``__BOOTSTRAP_STATE__`` and delete it immediately after consumption
