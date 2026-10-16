.. A new scriv changelog fragment.

Changed
-------

- The two customer purge commands swapped names so the one that deletes a
  single account is the plain one. ``bin/ots customers purge IDENTIFIER``
  purges one account (it was ``purge-one``). The inactivity sweep over many
  accounts is now ``bin/ots customers purge-inactive --older-than DURATION``
  (it was ``purge``). The old bulk invocation fails on its ``--older-than``
  option instead of running, and ``purge-one`` is no longer a command.

Fixed
-----

- ``bin/ots customers purge`` no longer takes minutes and a saturated
  core on a large deployment. Its deep preflight walked every organization,
  membership and custom domain record one at a time, loading each in full,
  and did so three times per purge. The three registries are now read with
  pipelined fetches of only the fields the preflight needs, at the plan and
  again after teardown but no longer for the deletion recheck in between, and
  the records a plan acts on are still re-loaded live before every decision.
