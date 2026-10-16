.. A new scriv changelog fragment.

Fixed
-----

- ``bin/ots customers purge-one`` no longer takes minutes and a saturated
  core on a large deployment. Its deep preflight walked every organization,
  membership and custom domain record one at a time, loading each in full,
  and did so three times per purge. The three registries are now listed once
  per purge with pipelined reads of only the fields the preflight needs, the
  post-teardown check refreshes that listing instead of repeating it, and
  the records a plan acts on are still re-loaded live before every decision.
