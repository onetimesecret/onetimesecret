.. A new scriv changelog fragment.

Added
-----

- ``bin/ots org doctor`` gained a sixth check: the class-level unique indexes.
  ``Organization`` declares five of them — ``contact_email``,
  ``stripe_customer_id``, ``stripe_subscription_id``, ``stripe_checkout_email``
  and ``billing_email`` — and Familia claims every one on each full save, so an
  entry mapping one of an org's values to a different objid makes every later
  full save fail with ``Key already exists``. That is a silent lockout: webhook
  updates, ``org reconcile`` and entitlement materialization all take the
  full-save path, and nothing surfaced the drift until one of them tried to
  write. The check names the three states it can find, per index: an entry that
  was never claimed (a fast write, or a write inside MULTI, neither of which
  can maintain a class-level index), an entry pointing at an org that was
  deleted or has since moved to a different value, and two live organizations
  carrying the same value.

- ``--repair`` fixes the two mechanical states — it claims a missing entry and
  repoints a stale one. Two live organizations sharing one indexed value is
  reported and never auto-repaired: for a Stripe field, choosing the canonical
  org means reading which one the subscription actually references, so the
  report carries both sides' extid, plan, subscription status and owner and
  leaves the call to an operator. The duplicate test runs before the stale test
  and does not depend on where the index points, so ``--repair`` cannot award a
  contested value to whichever org the scan happened to reach first.

- ``bin/ots org doctor --all`` additionally sweeps each of those indexes for
  entries no live organization carries. Those are invisible to a per-org check
  — the org that would have reported them is gone — and each one blocks
  whichever organization tries to claim that value next. ``--repair`` removes
  them; entries a live organization still contests are left for the per-org
  check.

- Every ``--repair`` write to an index is a compare-and-set against the value
  the diagnosis was read from, and every sweep deletion a compare-and-delete
  against the value seen when the entry was classified. Diagnosis and repair
  are separate round trips, and the values involved are exactly the ones a
  Stripe webhook or an ``org reconcile`` is free to claim in between; a blind
  write would erase that valid claim and re-open the lockout the check exists
  to close. An entry that moved is left as found and reported instead.

- Check 6 completes its map of which organizations carry which value before
  reporting or repairing anything, so a single-org run cannot mistake two
  organizations contesting an unclaimed value for a plain missing entry and
  quietly award it. The scan is lazy: an organization whose index entries are
  already correct never triggers it.

Fixed
-----

- Three of the five indexed fields are email addresses. They index their
  entries verbatim, but nothing a human reads — log line, issue message, JSON
  report — now carries one in the clear, matching how the doctor already
  obscures an organization owner's address.

AI Assistance
-------------

- Claude implemented the check, the index sweep and their repairs, extended the
  shared ``org_doctor_issues`` spec helper so ops that produce an organization
  assert the new invariant across every index too, and wrote the tryouts
  covering all three drift states, both repairs, the compare-and-set repair
  path, a non-Stripe index, the legacy JSON-encoded index values that would
  otherwise read as a conflict, and a guard asserting the checked list still
  matches what ``Organization`` declares.
