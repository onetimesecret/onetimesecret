.. A new scriv changelog fragment.

Added
-----

- ``bin/ots org doctor`` gained a sixth check: the ``stripe_customer_id``
  unique index. ``Organization`` claims that class-level index on every full
  save, so an entry mapping an org's Stripe customer id to a different objid
  makes every later full save fail with ``Key already exists`` — a silent
  lockout, since webhook updates, ``org reconcile`` and entitlement
  materialization all take the full-save path. Nothing surfaced the drift
  until one of them tried to write. The check names the three states it can
  find: an entry that was never claimed (a fast write, or a write inside
  MULTI, neither of which can maintain a class-level index), an entry pointing
  at an org that was deleted or has since moved to a different Stripe
  customer, and two live organizations carrying one Stripe customer id.

- ``--repair`` fixes the two mechanical states — it claims a missing entry and
  repoints a stale one. Two live organizations sharing a Stripe customer is
  reported and never auto-repaired: choosing the canonical org means reading
  which one the Stripe subscription actually references, so the report carries
  both sides' extid, plan, subscription status and owner and leaves the call
  to an operator. The duplicate test runs before the stale test and does not
  depend on where the index points, so ``--repair`` cannot award a contested
  customer id to whichever org the scan happened to reach first.

- ``bin/ots org doctor --all`` additionally sweeps
  ``organization:stripe_customer_id_index`` for entries no live organization
  carries. Those are invisible to a per-org check — the org that would have
  reported them is gone — and each one blocks whichever organization tries to
  claim that Stripe customer id next. ``--repair`` removes them; entries a
  live organization still contests are left for the per-org check.

- Every ``--repair`` write to the index is a compare-and-set against the value
  the diagnosis was read from, and every sweep deletion a compare-and-delete
  against the value seen when the entry was classified. Diagnosis and repair
  are separate round trips, and the ids involved are exactly the ones a Stripe
  webhook or an ``org reconcile`` is free to claim in between; a blind write
  would erase that valid claim and re-open the lockout the check exists to
  close. An entry that moved is left as found and reported instead.

- Check 6 completes its map of which organizations carry which Stripe customer
  id before reporting or repairing anything, so a single-org run cannot mistake
  two organizations contesting an unclaimed id for a plain missing entry and
  quietly award it. The scan is lazy: an organization whose index entry is
  already correct never triggers it.

AI Assistance
-------------

- Claude implemented the check, the index sweep and their repairs, extended
  the shared ``org_doctor_issues`` spec helper so ops that produce an
  organization assert the new invariant too, and wrote the tryouts covering
  all three drift states, both repairs, the compare-and-set repair path, and
  the legacy JSON-encoded index values that would otherwise read as a
  conflict.
