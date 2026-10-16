.. A new scriv changelog fragment.

Fixed
-----

- ``bin/ots customers purge-one`` no longer takes minutes and a saturated
  core on a large deployment. Its deep preflight walked every organization,
  membership and custom domain record one at a time, loading each in full,
  and did so three times per purge. The three registries are now read with
  pipelined fetches of only the fields the preflight needs, at the plan and
  again after teardown but no longer for the deletion recheck in between, and
  the records a plan acts on are still re-loaded live before every decision.
